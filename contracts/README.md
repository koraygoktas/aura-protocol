# AURA Protocol

> **Autonomous Risk-Adaptive Lending Engine with Zero-Knowledge Proof Verification**

AURA Protocol is a decentralized, risk-adaptive lending engine built on EVM that integrates on-chain zero-knowledge proof (ZK-SNARK) verification, dynamic Loan-to-Value (LTV) ratios, and multi-layered anti-flash-loan protections.

---

## 🌟 Key Features

* **ZK-Verified Risk Scoring:** Leverages ZK-SNARK proofs to verify off-chain risk calculations (e.g., credit/behavior scoring) without compromising sensitive user data.
* **Cryptographic Proof Binding:** Proofs are bound to `msg.sender` to eliminate front-running and proof-theft vulnerabilities in the mempool.
* **Replay & Expiration Protection:** Enforces unique nonces per user and validity timestamps (`validUntil`) to prevent proof re-use.
* **Dynamic LTV Architecture:** Adjusts borrowing power adaptively based on the user's verified risk score:
  * **Tier 1 (0–25):** 90% LTV
  * **Tier 2 (26–50):** 75% LTV
  * **Tier 3 (51–75):** 60% LTV
  * **Tier 4 (76–100):** 45% LTV
* **Anti-Flash-Loan Safeguards:** Action-specific cooldown intervals (1-minute withdrawal cooldown, 5-minute borrow cooldown) to mitigate flash-loan exploits and price manipulation.
* **Tiered Soft & Hard Liquidations:** Prevents catastrophic liquidations by enforcing a 50% maximum liquidation cap (`MAX_LIQUIDATION_RATIO`) per interaction alongside grace periods.

---

## 🏗 System Architecture

                        ```
                        +-------------------+
                        |   Mock Oracle     |
                        +---------+---------+
                                |
                                v
+------------------+   +--------+----------+   +-------------------+
|   AuraVerifier   |<--|  AuraCoreEngine   |-->|   AuraSentinel    |
| (ZK Verification)|   |   (Core Logic)    |   | (Health & Liq.)   |
+------------------+   +--------+----------+   +-------------------+
|
+------------+------------+
|                         |
v                         v
+-----------------+       +-----------------+
| MockCollateral  |       |    MockDebt     |
|  (mCOLL Token)  |       |  (mDEBT Token)  |
+-----------------+       +-----------------+

### Core Contracts

* **`AuraCoreEngine.sol`**: Central entry point handling deposits, borrows (`borrowWithZK`), repayments, collateral withdrawals, and liquidations.
* **`AuraSentinel.sol`**: Health factor computation and liquidation pipeline manager.
* **`AuraVerifier.sol`**: Verification contract validating ZK proofs, nonce state, and borrower binding.
* **`MockERC20.sol`**: Test tokens simulating Collateral (`mCOLL`) and Debt (`mDEBT`).
* **`MockOracle.sol`**: Configurable price feed for deterministic collateral valuation.

---

## 📜 Verified Deployments (Sepolia Testnet)

All contracts are deployed to the **Sepolia Testnet (Chain ID: 11155111)** and verified on Sourcify (`exact_match`):

| Contract | Address |
| :--- | :--- |
| **AuraCoreEngine** | `0x38003354968314BfC709C512D2E243eEA3C2D58C` |
| **AuraVerifier** | `0x6436c1c5073F099A50827a97551f188e8aA9C2f9` |
| **AuraSentinel** | `0xACb42493B545BcA436E384d735ad0dfd70884121` |
| **Mock Collateral (mCOLL)** | `0x403BdB7dc27Ce044a1B6f8F12d172263b2523091` |
| **Mock Debt (mDEBT)** | `0xE4f9Bd6008e0d377497ac2B224CB62EDa6033806` |
| **Mock Oracle** | `0x254e7C23AAC7cAd4dEd839bD202cF4bDCeD1E5f3` |

---

## 🧪 Testing & Verification

The protocol includes complete unit tests and property-based invariant fuzzing powered by Foundry:

```bash
# Run all unit tests
forge test -vvv

# Run invariant / fuzzing test suite (128k+ calls)
forge test --match-contract AuraInvariantTest

Test Coverage Highlights:

Full coverage for ZK proof expiration, invalid nonces, and proof replay prevention.

Invariant tests verifying protocol solvency, collateral backing, and non-negative debt states.

💻 Running the Frontend Locally
The frontend is built with vanilla JavaScript and Web3.js.

Navigate to the frontend directory or serve the project root:

Bash
# Using Python
python -m http.server 5500

# Or using Node.js
npx serve frontend
Open http://127.0.0.1:5500 in your browser.

Connect your MetaMask wallet to Sepolia Testnet.

Deposit collateral, generate a bound ZK proof, and borrow against your collateral.

📄 License
This project is licensed under the MIT License.