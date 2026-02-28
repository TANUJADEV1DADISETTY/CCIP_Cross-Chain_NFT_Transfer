// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/CrossChainNFT.sol";
import "../src/CCIPNFTBridge.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address router = vm.envAddress("CCIP_ROUTER");
        address linkToken = vm.envAddress("LINK_TOKEN");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy CrossChainNFT
        CrossChainNFT nft = new CrossChainNFT("CCIP CrossChain NFT", "CCNFT", vm.addr(deployerPrivateKey));
        console.log("CrossChainNFT deployed to:", address(nft));

        // 2. Deploy CCIPNFTBridge
        CCIPNFTBridge bridge = new CCIPNFTBridge(router, linkToken, address(nft));
        console.log("CCIPNFTBridge deployed to:", address(bridge));

        // 3. Temporarily set bridge to deployer to pre-mint
        nft.setBridge(vm.addr(deployerPrivateKey));
        nft.mint(vm.addr(deployerPrivateKey), 1, "https://ipfs.io/ipfs/QmRL...token_uri_here");
        console.log("NFT #1 pre-minted to deployer");

        // 4. Set the actual bridge
        nft.setBridge(address(bridge));
        console.log("Bridge set in NFT contract");

        vm.stopBroadcast();
    }
}
