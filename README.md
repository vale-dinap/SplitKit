# SplitKit

**NFT fractionalization protocol: Split ERC721s into tradeable shares, redeem with 100% ownership. Gas-optimized minimal proxy architecture.**

## Overview

SplitKit enables anyone to fractionalize ERC721 NFTs into multiple ERC1155 "splits" that can be traded independently on any marketplace or DEX. The system uses ERC1155 to ensure that splits are fungible and natively compatible with NFT marketplaces, while enabling batch transfers with minimal gas costs. 

Original NFTs remain safely escrowed in smart contracts and can be redeemed anytime by an address owning 100% of the splits. There is no pricing logic by design - price discovery is handled entirely by free markets. While splits should theoretically trade at a portion of the underlying NFT's floor price, market dynamics can create interesting trading and arbitrage opportunities. In addition, a minimal, oracle-free architecture ensures robustness and a significantly reduced attack surface.

### Key Benefits

**🎯 Flexible Portfolio Management**: Own an expensive NFT but need liquidity? Fractionalize it and sell just 20-30% while maintaining majority ownership and upside exposure.

**💎 Democratized Access**: Enable smaller investors to own pieces of blue-chip NFTs - buy 0.1% of a Bored Ape instead of needing $50K+ for the whole asset.

**📈 Enhanced Liquidity**: Transform illiquid NFTs into tradeable assets with multiple price points and trading opportunities.

**⚖️ Risk Distribution**: Spread exposure across multiple partial positions rather than concentrated bets on whole NFTs.

### Key Features

- 🔀 **Fractionalize any ERC721** into 2 to 1,000,000 ERC1155 splits
- 💱 **Trade splits freely** on any NFT marketplace or DEX that supports ERC1155
- ⛽ **Gas optimized** with minimal proxy pattern and packed storage
- 🎨 **Preserves original NFT metadata** - splits display the same image as the original
- 📊 **Market-driven pricing** with natural arbitrage opportunities
- 🏗️ **Immutable and decentralized** - no admin keys or upgradeability

## Architecture

### Core Contracts

- **`SplitNFTFactory.sol`** - Factory contract that handles the NFT fractionalization
- **`SplitERC721.sol`** - Implementation contract for individual fractionalized NFTs
- **`ISplitERC721.sol`** - Clean external interface for the fractionalized NFTs, extending IERC1155
- **`ISplitERC721Errors.sol`** - Modular error definitions for better UX

### Design Principles

**Minimal Proxy Pattern**: Each fractionalized NFT gets its own contract instance via OpenZeppelin Clones, drastically reducing deployment costs while maintaining isolated state.

**Storage Optimization**: Struct packing reduces gas costs by ~40% through careful type sizing and slot arrangement.

**Market-Driven Economics**: No oracle dependencies or complex pricing mechanisms - the free market determines split values through natural arbitrage.

**Separation of Concerns**: Clean interface architecture enables better external integration and error handling.

## Quick Start

### Installation

#### Clone the repository
```bash
git clone https://github.com/vale-dinap/SplitKit.git
cd SplitKit
```

#### Install Foundry (recommended but optional)
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Deployment

⚠️ Important: Before deploying, update the placeholder image URL in `SplitERC721.sol`'s `contractURI` function:
```solidity
// Line ~140
'"image": "[URL]/split-logo.png"', // Replace with an image URL
```
(This should be replaced with some better logic)

#### Deploy the factory

##### Using Foundry
```bash
forge create SplitNFTFactory --rpc-url <YOUR_RPC_URL> --private-key <YOUR_PRIVATE_KEY>
```

##### Or using any framework of choice - no special dependencies required

### Basic Usage

```solidity
import { SplitNFTFactory } from "./SplitNFTFactory.sol";
import { ISplitERC721 } from "./ISplitERC721.sol";

// Use deployed factory address
SplitNFTFactory factory = SplitNFTFactory(FACTORY_ADDRESS);

// Approve factory to transfer your NFT
IERC721(nftContract).approve(address(factory), tokenId);

// Fractionalize NFT into 1000 splits
address splitContract = factory.splitNFT(nftContract, tokenId, 1000);

// Interact with splits using the interface
ISplitERC721 splits = ISplitERC721(splitContract);
uint256 balance = splits.balanceOf(owner, 0);
uint256 ownership = splits.ownershipFromSplits(balance);
```
### Frontend Integration

Use the interface files for type-safe interactions:
```javascript
// Import ABI from ISplitERC721.sol for frontend integration
import ISplitERC721 from './artifacts/ISplitERC721.sol/ISplitERC721.json';

// Contract instance
const splitContract = new ethers.Contract(splitAddress, ISplitERC721.abi, signer);
```

### Example Scenarios

**Scenario 1**: Bored Ape worth 50 ETH, split into 1000 shares
- Each split represents 0.1% ownership
- Fair value: ~0.05 ETH per split
- Market price discovery through trading

**Scenario 2**: Rare 1/1 artwork worth 10 ETH, split into 100 shares  
- Each split represents 1% ownership
- Fair value: ~0.1 ETH per split
- Enables broader collector participation

## Security Considerations

### Design Security

- **Immutable Contracts**: No admin keys, upgradeability, or owner privileges by design
- **Battle-tested Dependencies**: Built exclusively on OpenZeppelin's audited contracts
- **Minimal Attack Surface**: Simple, focused contracts with clear, limited responsibilities
- **No Oracle Risk**: Market-driven pricing eliminates oracle manipulation and external dependency risks
- **Reentrancy Protection**: Follows strict checks-effects-interactions pattern

### Code Quality

- **Custom Error Handling**: Gas-efficient custom errors with meaningful context
- **Comprehensive Input Validation**: All parameters validated before state changes
- **Interface Separation**: Clean modular architecture reduces integration risks

### Known Limitations And Considerations

- **Metadata Dependency**: The system relies on the metadata of the NFTs being fractionalized, the integrity of which is not guaranteed. Future versions could include backend services that cache NFT metadata at fractionalization time and generate enhanced metadata specifically for splits.
- **ERC721 Compliance**: Relies on proper ERC721 implementation of source NFTs. This should typically not be an issue, as improperly implemented NFTs would also be incompatible with major marketplaces and wallets.
- **Coordination Challenges**: Accumulating 100% of splits for redemption may be difficult due to distributed ownership. However, the practical benefits of NFT redemption versus simply trading liquid splits remain debatable.

### Audit Status
⚠️ **This protocol has not been audited. Use at your own risk**, especially for high-value NFTs. Consider professional audit before production deployment.

### Best Practices

- Test thoroughly on testnets before mainnet deployment
- Start with lower-value NFTs to validate market mechanics
- Update placeholder metadata before deployment

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow Solidity style guide
- Add comprehensive tests for new features  
- Update documentation for ABI changes
- Optimize for gas efficiency
- Maintain backwards compatibility

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contact

**Valerio Di Napoli**
- GitHub: [@vale-dinap](https://github.com/vale-dinap)
- X: [@valedinapoli](https://x.com/valedinapoli)
- LinkedIn: [@valeriodinapoli](https://linkedin.com/in/valeriodinapoli)

---

*Built with ⚡ for the future of NFT ownership*