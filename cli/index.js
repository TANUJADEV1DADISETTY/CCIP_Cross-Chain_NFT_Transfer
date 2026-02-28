require('dotenv').config();
const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
const { Command } = require('commander');
const chalk = require('chalk');
const { v4: uuidv4 } = require('uuid');

const program = new Command();

// Paths
const LOG_FILE = path.join(__dirname, '../logs/transfers.log');
const DATA_FILE = path.join(__dirname, '../data/nft_transfers.json');
const DEPLOYMENT_FILE = path.join(__dirname, '../deployment.json');

// Ensure directories exist
if (!fs.existsSync(path.join(__dirname, '../logs'))) fs.mkdirSync(path.join(__dirname, '../logs'));
if (!fs.existsSync(path.join(__dirname, '../data'))) fs.mkdirSync(path.join(__dirname, '../data'));

function logMessage(message) {
    const timestamp = new Date().toISOString();
    const formattedMessage = `[${timestamp}] ${message}\n`;
    fs.appendFileSync(LOG_FILE, formattedMessage);
    console.log(message);
}

function updateTransferData(transfer) {
    let data = [];
    if (fs.existsSync(DATA_FILE)) {
        try {
            data = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
        } catch (e) {
            data = [];
        }
    }
    data.push(transfer);
    fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 4));
}

program
    .name('nft-bridge-cli')
    .description('CLI to transfer NFTs cross-chain using Chainlink CCIP')
    .version('1.0.0');

program
    .command('transfer')
    .requiredOption('--tokenId <number>', 'Token ID to transfer')
    .requiredOption('--from <chain>', 'Source chain (avalanche-fuji or arbitrum-sepolia)')
    .requiredOption('--to <chain>', 'Destination chain')
    .requiredOption('--receiver <address>', 'Receiver address on destination chain')
    .action(async (options) => {
        try {
            const { tokenId, from, to, receiver } = options;
            logMessage(chalk.blue(`Initiating transfer of token ${tokenId} from ${from} to ${to} for receiver ${receiver}`));

            // Load deployment data
            if (!fs.existsSync(DEPLOYMENT_FILE)) {
                throw new Error('deployment.json not found. Please deploy contracts first.');
            }
            const deployment = JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, 'utf8'));

            const chainMapping = {
                'avalanche-fuji': 'avalamchefuji',
                'arbitrum-sepolia': 'arbitrumSepolia'
            };

            const mappedFrom = chainMapping[from] || from;
            const mappedTo = chainMapping[to] || to;

            const sourceConfig = deployment[mappedFrom];
            const destConfig = deployment[mappedTo];

            if (!sourceConfig || !destConfig) {
                throw new Error(`Invalid chain configuration in deployment.json for ${from} (${mappedFrom}) or ${to} (${mappedTo})`);
            }

            const rpcUrl = from === 'avalanche-fuji' ? process.env.FUJI_RPC_URL : process.env.ARBITRUM_SEPOLIA_RPC_URL;
            const privateKey = process.env.PRIVATE_KEY;

            if (!rpcUrl || !privateKey) {
                throw new Error('RPC URL or Private Key missing in .env');
            }

            const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
            const wallet = new ethers.Wallet(privateKey, provider);

            // ABIs (minimal for the functions we need)
            const bridgeAbi = [
                "function sendNFT(uint64 destinationChainSelector, address receiver, uint256 tokenId) external returns (bytes32 messageId)",
                "event NFTSent(bytes32 indexed messageId, uint64 indexed destinationChainSelector, address receiver, uint256 tokenId, string tokenURI)"
            ];
            const nftAbi = [
                "function tokenURI(uint256 tokenId) public view returns (string memory)",
                "function name() public view returns (string memory)",
                "function symbol() public view returns (string memory)"
            ];

            const bridgeContract = new ethers.Contract(sourceConfig.beidgeContractAddress, bridgeAbi, wallet);
            const nftContract = new ethers.Contract(sourceConfig.nftContractAddress, nftAbi, wallet);

            // Fetch metadata before burning/transferring
            logMessage("Fetching NFT metadata...");
            let name = "Unknown";
            let tokenUri = "";
            try {
                name = await nftContract.name();
                tokenUri = await nftContract.tokenURI(tokenId);
            } catch (e) {
                logMessage(chalk.yellow("Warning: Could not fetch NFT metadata."));
            }

            // Chain Selectors (hardcoded for Fuji and Arbitrum Sepolia CCIP)
            const chainSelectors = {
                'avalanche-fuji': '14767482510784806043',
                'arbitrum-sepolia': '3478487238524512106'
            };

            const destSelector = chainSelectors[to];
            if (!destSelector) {
                throw new Error(`Chain selector not found for ${to}`);
            }

            logMessage("Sending transaction...");
            const tx = await bridgeContract.sendNFT(destSelector, receiver, tokenId);
            logMessage(chalk.green(`Source Transaction Hash: ${tx.hash}`));

            const receipt = await tx.wait();
            logMessage(chalk.green("Transaction confirmed!"));

            // Extract MessageId from event
            const event = receipt.logs.map(log => {
                try {
                    return bridgeContract.interface.parseLog(log);
                } catch (e) { return null; }
            }).find(parsed => parsed && parsed.name === 'NFTSent');

            const messageId = event ? event.args.messageId : "Pending";
            logMessage(chalk.green(`CCIP Message ID: ${messageId}`));

            const transferEntry = {
                transferId: uuidv4(),
                tokenId: tokenId.toString(),
                sourceChain: from,
                destinationChain: to,
                sender: wallet.address,
                receiver: receiver,
                ccipMessageId: messageId,
                sourceTxHash: tx.hash,
                destinationTxHash: null,
                status: 'initiated',
                metadata: {
                    name: name,
                    description: `Transferred from ${from}`,
                    image: tokenUri // Using tokenURI as image for simplicity in this bridge
                },
                timestamp: new Date().toISOString()
            };

            updateTransferData(transferEntry);
            logMessage(chalk.cyan("Transfer record saved to data/nft_transfers.json"));

        } catch (error) {
            logMessage(chalk.red(`Error: ${error.message}`));
            process.exit(1);
        }
    });

program.parse();
