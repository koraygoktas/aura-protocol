# AURA Protocol Frontend

Modern, responsive dashboard for the AURA DeFi lending protocol with ZK-verified borrowing.

## Features

- **Wallet Connection**: MetaMask integration for seamless wallet connection
- **Dashboard**: Real-time display of collateral, debt, health factor, and risk score
- **Deposit**: Deposit collateral tokens to the protocol
- **Borrow with ZK Verification**: Borrow against collateral with ZK-proof verified risk scores
- **Dynamic LTV**: Risk-adaptive loan-to-value ratios based on ZK-verified risk scores
- **Repay**: Repay borrowed tokens
- **Withdraw**: Withdraw collateral tokens (if position is healthy)

## Risk-Based LTV Tiers

- **Tier 1 (Risk Score 0-25)**: 90% LTV
- **Tier 2 (Risk Score 26-50)**: 75% LTV  
- **Tier 3 (Risk Score 51-75)**: 60% LTV
- **Tier 4 (Risk Score 76-100)**: 45% LTV

## Setup

1. Open `index.html` in a modern web browser
2. Click "Connect Wallet" to connect your MetaMask wallet
3. Ensure you're on the correct network (where contracts are deployed)
4. Update contract addresses in the JavaScript section:
   ```javascript
   const CONTRACT_ADDRESSES = {
       collateralToken: '0x...', // Deployed collateral token address
       debtToken: '0x...',      // Deployed debt token address
       engine: '0x...',         // Deployed AuraCoreEngine address
       verifier: '0x...'        // Deployed AuraVerifier address
   };
   ```

## Current Status

The frontend is currently in **demo mode** with mock data. To connect to the actual blockchain:

1. Deploy the smart contracts to your chosen network
2. Update the contract addresses in the JavaScript
3. Uncomment the actual contract calls in the JavaScript functions
4. Ensure Web3.js is properly configured for your network

## Dependencies

- Web3.js (loaded via CDN)
- MetaMask browser extension

## Future Enhancements

- Connect to actual deployed contracts
- Integrate with the ZK-ML proof generation service
- Add transaction history
- Implement real-time price feeds
- Add liquidation warnings
- Multi-chain support
- Advanced analytics and charts

## Security Notes

- Always verify contract addresses before connecting
- Ensure you're interacting with the correct network
- Review transaction details before confirming
- The demo mode uses mock data for testing purposes

## License

MIT
