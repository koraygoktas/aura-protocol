# AURA Protocol Deployment Scripts

## DeployAura.s.sol

Foundry deployment script for deploying the AURA Protocol to Sepolia testnet.

### Prerequisites

1. Create a `.env` file in the `contracts/` directory with the following variables:
   ```
   SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY"
   PRIVATE_KEY="your_private_key"
   ETHERSCAN_API_KEY="your_etherscan_api_key"
   ```

2. Ensure you have Sepolia ETH in your deployer wallet for gas fees.

### Deployment Steps

1. **Build the contracts:**
   ```bash
   forge build
   ```

2. **Deploy to Sepolia:**
   ```bash
   forge script script/DeployAura.s.sol:DeployAura --rpc-url $SEPOLIA_RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
   ```

3. **Or use the .env file directly:**
   ```bash
   source .env
   forge script script/DeployAura.s.sol:DeployAura --rpc-url $SEPOLIA_RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
   ```

### Deployment Order

The script deploys contracts in the following order to handle circular dependencies:

1. **AuraVerifier** - ZK proof verification contract
2. **MockOracle** - Price oracle for testing
3. **Mock Collateral Token (mCOLL)** - Collateral token for deposits
4. **Mock Debt Token (mDEBT)** - Debt token for borrowing
5. **AuraSentinel** - Liquidation management (with temporary deployer address)
6. **AuraCoreEngine** - Main lending engine
7. **Update Sentinel** - Sets correct engine address in Sentinel
8. **Mint Tokens** - Initial token distribution to deployer and engine

### Post-Deployment

After deployment, the script will output all contract addresses:

```
=== Deployment Summary ===
Deployer: 0x...
AuraVerifier: 0x...
AuraSentinel: 0x...
AuraCoreEngine: 0x...
Mock Collateral (mCOLL): 0x...
Mock Debt (mDEBT): 0x...
MockOracle: 0x...
```

### Verification

The script automatically verifies contracts on Etherscan if you provide the `ETHERSCAN_API_KEY`.

### Initial Token Distribution

- **Deployer**: 1,000,000 mCOLL and 1,000,000 mDEBT
- **AuraCoreEngine**: 10,000,000 mDEBT (for lending pool)

### Frontend Integration

Update the frontend `index.html` with the deployed contract addresses:

```javascript
const CONTRACT_ADDRESSES = {
    collateralToken: '0x...', // Deployed mCOLL address
    debtToken: '0x...',      // Deployed mDEBT address
    engine: '0x...',         // Deployed AuraCoreEngine address
    verifier: '0x...'        // Deployed AuraVerifier address
};
```

### Security Notes

- Never commit your `.env` file to version control
- Use a dedicated deployer wallet with minimal funds
- Verify contract addresses on Etherscan before using in production
- Test thoroughly on testnet before mainnet deployment
