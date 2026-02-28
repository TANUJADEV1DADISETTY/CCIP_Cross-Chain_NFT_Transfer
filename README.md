# Chainlink CCIP Cross-Chain NFT Bridge

This project implements a cross-chain NFT bridge using Chainlink's Cross-Chain Interoperability Protocol (CCIP). It allows for transferring NFTs between Avalanche Fuji and Arbitrum Sepolia while preserving metadata.

## Features
- **Burn-and-Mint Mechanism**: Ensures constant supply across chains.
- **Metadata Preservation**: Token URI is transferred along with the token.
- **Access Control**: Only the bridge contract can mint NFTs.
- **CLI Tool**: Easy initiation of cross-chain transfers.
- **Dockerized Environment**: Consistent setup for the CLI.

## Project Structure
- `src/`: Solidity smart contracts (`CrossChainNFT.sol`, `CCIPNFTBridge.sol`).
- `script/`: Foundry deployment scripts.
- `cli/`: Node.js CLI tool for interacting with the bridge.
- `data/`: JSON file for tracking transfers.
- `logs/`: Transaction logs.

## Setup
1. Copy `.env.example` to `.env` and fill in your `PRIVATE_KEY` and RPC URLs.
2. Install dependencies: `npm install`.
3. Build contracts: `forge build`.
4. Deploy contracts to both chains using Foundry.
5. Update `deployment.json` with the deployed addresses.

## CLI Usage
Execute the transfer via Docker:
```bash
docker-compose up -d --build
docker exec ccip-nft-bridge-cli npm run transfer -- --tokenId=1 --from=avalanche-fuji --to=arbitrum-sepolia --receiver=0xYourAddress
```

## Pre-minted Test Asset
- **Source Chain**: Avalanche Fuji
- **Token ID**: 1
- **Owner**: Deployer Wallet (defined by `PRIVATE_KEY`)
- **Metadata**: [Metadata Example](https://ipfs.io/ipfs/QmRL...token_uri_here)

## Security
This project uses `Ownable` for administrative functions and robust access control for cross-chain minting. Only verified CCIP messages from the authorized bridge on the source chain trigger the minting process.
