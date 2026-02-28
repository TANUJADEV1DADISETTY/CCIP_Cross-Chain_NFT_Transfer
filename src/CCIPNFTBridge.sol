// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./CrossChainNFT.sol";

contract CCIPNFTBridge is CCIPReceiver, IERC721Receiver {
    // Contract dependencies
    CrossChainNFT public immutable nft;
    IRouterClient public router;
    IERC20 public linkToken;

    // State variables
    mapping(uint64 => address) public bridgePeers;
    address public owner;

    // Events
    event NFTSent(
        bytes32 messageId,
        uint64 destinationChainSelector,
        address receiver,
        uint256 tokenId,
        string tokenURI
    );

    event NFTReceived(
        bytes32 messageId,
        uint64 sourceChainSelector,
        address sender,
        uint256 tokenId,
        string tokenURI
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(
        address _router,
        address _link,
        address _nft
    ) CCIPReceiver(_router) {
        router = IRouterClient(_router);
        linkToken = IERC20(_link);
        nft = CrossChainNFT(_nft);
        owner = msg.sender;
    }

    // Function to set peer bridge addresses
    function setBridgePeer(uint64 _selector, address _peer) external onlyOwner {
        bridgePeers[_selector] = _peer;
    }

    // Main function to initiate the NFT transfer
    function sendNFT(
        uint64 destinationChainSelector,
        address receiver,
        uint256 tokenId
    ) external returns (bytes32 messageId) {
        address peer = bridgePeers[destinationChainSelector];
        require(peer != address(0), "Peer bridge not set");

        string memory tokenURI = nft.tokenURI(tokenId);

        // Burn the NFT on the source chain
        nft.burn(tokenId);

        // Prepare the CCIP message
        bytes memory data = abi.encode(receiver, tokenId, tokenURI);
        
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(peer),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 400_000})
            ),
            feeToken: address(linkToken)
        });

        // Get the fee required to send the message
        uint256 fees = router.getFee(destinationChainSelector, evm2AnyMessage);

        if (fees > linkToken.balanceOf(address(this))) {
            revert("Insufficient LINK balance");
        }

        // approve the Router to spend LINK tokens on contract's behalf
        linkToken.approve(address(router), fees);

        // Send the message through the router and store the returned message ID
        messageId = router.ccipSend(destinationChainSelector, evm2AnyMessage);

        emit NFTSent(messageId, destinationChainSelector, receiver, tokenId, tokenURI);

        return messageId;
    }

    // Callback function to receive messages from CCIP Router
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        // Validate sender and source chain
        address expectedSender = bridgePeers[message.sourceChainSelector];
        require(expectedSender != address(0), "Source chain not allowlisted");
        require(abi.decode(message.sender, (address)) == expectedSender, "Invalid sender");

        (address receiver, uint256 tokenId, string memory tokenURI) = abi.decode(
            message.data,
            (address, uint256, string)
        );

        // Mint the NFT on the destination chain
        // CrossChainNFT.mint should handle internal idempotency if needed, 
        // but here we just call it.
        nft.mint(receiver, tokenId, tokenURI);

        emit NFTReceived(message.messageId, message.sourceChainSelector, abi.decode(message.sender, (address)), tokenId, tokenURI);
    }

    // Estimate transfer cost in LINK tokens
    function estimateTransferCost(uint64 destinationChainSelector) external view returns (uint256) {
        address peer = bridgePeers[destinationChainSelector];
        // If peer not set, use a dummy for estimation
        address receiverPeer = peer == address(0) ? address(this) : peer;

        bytes memory data = abi.encode(address(this), 0, "tokenURI");
        
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverPeer),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 400_000})
            ),
            feeToken: address(linkToken)
        });

        return router.getFee(destinationChainSelector, evm2AnyMessage);
    }

    // Required for safe NFT transfers to this contract
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
