// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AuraSentinel.sol";
import "./AuraVerifier.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockOracle.sol";

/**
 * @title AuraCoreEngine
 * @notice Core lending engine for AURA Protocol with ZK verification, dynamic LTV, and anti-flash-loan protection.
 * @dev Manages deposits, borrows, repayments, and liquidations with risk-adaptive parameters.
 */
contract AuraCoreEngine {
    // immutable contracts
    AuraSentinel public immutable sentinel;
    AuraVerifier public immutable verifier;
    MockERC20 public immutable collateralToken;
    MockERC20 public immutable debtToken;
    MockOracle public immutable oracle;

    // user positions
    struct Position {
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 lastActionTimestamp;
        uint256 riskScore;
    }

    mapping(address => Position) public positions;

    // dynamic LTV parameters based on risk score (0-100)
    // riskScore 0-25: 90% LTV
    // riskScore 26-50: 75% LTV
    // riskScore 51-75: 60% LTV
    // riskScore 76-100: 45% LTV
    uint256 public constant RISK_TIER_1_MAX = 25;
    uint256 public constant RISK_TIER_2_MAX = 50;
    uint256 public constant RISK_TIER_3_MAX = 75;
    
    uint256 public constant LTV_TIER_1 = 90; // 90%
    uint256 public constant LTV_TIER_2 = 75; // 75%
    uint256 public constant LTV_TIER_3 = 60; // 60%
    uint256 public constant LTV_TIER_4 = 45; // 45%

    // anti-flash-loan protection
    uint256 public constant ACTION_COOLDOWN = 1 minutes; // minimum time between sensitive actions
    uint256 public constant BORROW_COOLDOWN = 5 minutes; // minimum time between borrows

    // protocol parameters
    uint256 public constant TARGET_RATIO = 110; // 110% (1.1x) for health factor calculations
    uint256 public constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators
    uint256 public constant PROOF_VALIDITY_PERIOD = 1 hours; // ZK proofs valid for 1 hour
    uint256 public constant MAX_LIQUIDATION_RATIO = 50; // Max 50% debt can be liquidated at once

    // events
    event Deposited(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount, uint256 riskScore);
    event Repaid(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 debtRepaid, uint256 collateralSeized);
    event RiskScoreUpdated(address indexed user, uint256 oldRiskScore, uint256 newRiskScore);

    // errors
    error InsufficientCollateral();
    error PositionHealthy();
    error CooldownNotMet();
    error InvalidProof();
    error InvalidRiskScore();
    error InsufficientBalance();
    error ZeroAmount();
    error SameBlockAction();
    error ProofExpired();
    error InvalidNonce();
    error ProofAlreadyUsed();
    error InvalidProofBinding();

    modifier onlyPositiveAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    constructor(
        address _sentinel,
        address _verifier,
        address _collateralToken,
        address _debtToken,
        address _oracle
    ) {
        sentinel = AuraSentinel(_sentinel);
        verifier = AuraVerifier(_verifier);
        collateralToken = MockERC20(_collateralToken);
        debtToken = MockERC20(_debtToken);
        oracle = MockOracle(_oracle);
    }

    /**
     * @notice Get dynamic LTV based on risk score.
     * @param riskScore Risk score from ZK verification (0-100).
     * @return LTV percentage (scaled to 100).
     */
    function getDynamicLTV(uint256 riskScore) public pure returns (uint256) {
        if (riskScore <= RISK_TIER_1_MAX) {
            return LTV_TIER_1;
        } else if (riskScore <= RISK_TIER_2_MAX) {
            return LTV_TIER_2;
        } else if (riskScore <= RISK_TIER_3_MAX) {
            return LTV_TIER_3;
        } else {
            return LTV_TIER_4;
        }
    }

    /**
     * @notice Get maximum borrowable amount based on collateral and risk score.
     * @param collateralAmount Amount of collateral.
     * @param riskScore Risk score from ZK verification.
     * @return Maximum borrowable amount in debt token.
     */
    function getMaxBorrowAmount(uint256 collateralAmount, uint256 riskScore) public view returns (uint256) {
        uint256 ltv = getDynamicLTV(riskScore);
        uint256 collateralPrice = oracle.getPrice();
        uint256 collateralValue = (collateralAmount * collateralPrice) / 1e18;
        return (collateralValue * ltv) / 100;
    }

    /**
     * @notice Get current health factor of a position.
     * @param user User address.
     * @return Health factor (scaled to 1e18, >= 1e18 is healthy).
     */
    function getHealthFactor(address user) public view returns (uint256) {
        Position memory pos = positions[user];
        if (pos.debtAmount == 0) return type(uint256).max;
        
        uint256 targetRatio = TARGET_RATIO * 1e16; // 1.1e18
        return sentinel.calculateHealthFactor(
            pos.collateralAmount,
            pos.debtAmount,
            oracle.getPrice(),
            targetRatio
        );
    }

    /**
     * @notice Deposit collateral to the protocol.
     * @param amount Amount of collateral to deposit.
     */
    function deposit(uint256 amount) external onlyPositiveAmount(amount) {
        collateralToken.transferFrom(msg.sender, address(this), amount);
        
        positions[msg.sender].collateralAmount += amount;
        positions[msg.sender].lastActionTimestamp = block.timestamp;
        
        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Borrow with ZK proof verification with replay and expiration protection.
     * @param amount Amount to borrow.
     * @param proof ZK-SNARK proof.
     * @param publicInputs Public inputs [borrowerAddress, riskScore].
     * @param validUntil Timestamp until which the proof is valid.
     * @param nonce Unique nonce for the user to prevent replay attacks.
     */
    function borrowWithZK(
        uint256 amount,
        bytes calldata proof,
        uint256[] calldata publicInputs,
        uint256 validUntil,
        uint256 nonce
    ) external onlyPositiveAmount(amount) {
        // verify ZK proof with replay and expiration protection
        // The verifier will revert with specific errors if validation fails
        bool proofValid = verifier.verifyProof(msg.sender, proof, publicInputs, validUntil, nonce);
        if (!proofValid) {
            revert InvalidProof();
        }

        // verify public inputs
        if (publicInputs.length < 2) revert InvalidProof();
        
        uint256 riskScore = publicInputs[1];
        if (riskScore > 100) revert InvalidRiskScore();

        // check anti-flash-loan cooldown (only if user has previous actions)
        Position storage pos = positions[msg.sender];
        if (pos.lastActionTimestamp > 0 && block.timestamp < pos.lastActionTimestamp + BORROW_COOLDOWN) {
            revert CooldownNotMet();
        }

        // calculate maximum borrowable
        uint256 maxBorrow = getMaxBorrowAmount(pos.collateralAmount, riskScore);
        uint256 newDebt = pos.debtAmount + amount;
        
        if (newDebt > maxBorrow) {
            revert InsufficientCollateral();
        }

        // update position
        uint256 oldRiskScore = pos.riskScore;
        pos.debtAmount = newDebt;
        pos.riskScore = riskScore;
        pos.lastActionTimestamp = block.timestamp;

        // transfer debt tokens
        debtToken.transfer(msg.sender, amount);

        emit Borrowed(msg.sender, amount, riskScore);
        if (oldRiskScore != riskScore) {
            emit RiskScoreUpdated(msg.sender, oldRiskScore, riskScore);
        }
    }

    /**
     * @notice Regular borrow without ZK verification (for testing/emergency).
     * @param amount Amount to borrow.
     * @param riskScore Risk score to use for LTV calculation.
     */
    function borrow(uint256 amount, uint256 riskScore) external onlyPositiveAmount(amount) {
        if (riskScore > 100) revert InvalidRiskScore();

        // check anti-flash-loan cooldown (only if user has previous actions)
        Position storage pos = positions[msg.sender];
        if (pos.lastActionTimestamp > 0 && block.timestamp < pos.lastActionTimestamp + BORROW_COOLDOWN) {
            revert CooldownNotMet();
        }

        // calculate maximum borrowable
        uint256 maxBorrow = getMaxBorrowAmount(pos.collateralAmount, riskScore);
        uint256 newDebt = pos.debtAmount + amount;
        
        if (newDebt > maxBorrow) {
            revert InsufficientCollateral();
        }

        // update position
        uint256 oldRiskScore = pos.riskScore;
        pos.debtAmount = newDebt;
        pos.riskScore = riskScore;
        pos.lastActionTimestamp = block.timestamp;

        // transfer debt tokens
        debtToken.transfer(msg.sender, amount);

        emit Borrowed(msg.sender, amount, riskScore);
        if (oldRiskScore != riskScore) {
            emit RiskScoreUpdated(msg.sender, oldRiskScore, riskScore);
        }
    }

    /**
     * @notice Repay debt.
     * @param amount Amount to repay.
     */
    function repay(uint256 amount) external onlyPositiveAmount(amount) {
        Position storage pos = positions[msg.sender];
        
        if (amount > pos.debtAmount) {
            amount = pos.debtAmount;
        }

        debtToken.transferFrom(msg.sender, address(this), amount);
        pos.debtAmount -= amount;
        pos.lastActionTimestamp = block.timestamp;

        // if debt is fully repaid, resolve soft liquidation
        if (pos.debtAmount == 0) {
            sentinel.resolveSoftLiquidation(msg.sender);
        }

        emit Repaid(msg.sender, amount);
    }

    /**
     * @notice Withdraw collateral (only if position is healthy).
     * @param amount Amount to withdraw.
     */
    function withdraw(uint256 amount) external onlyPositiveAmount(amount) {
        Position storage pos = positions[msg.sender];
        
        if (amount > pos.collateralAmount) {
            revert InsufficientBalance();
        }

        // check if position remains healthy after withdrawal
        uint256 newCollateral = pos.collateralAmount - amount;
        uint256 maxBorrow = getMaxBorrowAmount(newCollateral, pos.riskScore);
        
        if (pos.debtAmount > maxBorrow) {
            revert InsufficientCollateral();
        }

        // check cooldown (only if user has previous actions)
        if (pos.lastActionTimestamp > 0 && block.timestamp < pos.lastActionTimestamp + ACTION_COOLDOWN) {
            revert CooldownNotMet();
        }

        pos.collateralAmount = newCollateral;
        pos.lastActionTimestamp = block.timestamp;

        collateralToken.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Liquidate an unhealthy position with proper liquidation bonus.
     * @param user User to liquidate.
     * @param debtToRepay Amount of debt to repay.
     */
    function liquidate(address user, uint256 debtToRepay) external onlyPositiveAmount(debtToRepay) {
        Position storage pos = positions[user];
        
        if (pos.debtAmount == 0) revert PositionHealthy();

        // check health factor
        uint256 healthFactor = getHealthFactor(user);
        if (healthFactor >= 1e18) revert PositionHealthy();

        // enforce max liquidation ratio (cannot liquidate more than MAX_LIQUIDATION_RATIO at once)
        uint256 maxLiquidatableDebt = (pos.debtAmount * MAX_LIQUIDATION_RATIO) / 100;
        if (debtToRepay > maxLiquidatableDebt) {
            debtToRepay = maxLiquidatableDebt;
        }

        // process liquidation through sentinel
        uint256 targetRatio = TARGET_RATIO * 1e16;
        (uint256 actualDebtToRepay, uint256 collateralToSeize,) = 
            sentinel.processLiquidation(
                user,
                pos.collateralAmount,
                pos.debtAmount,
                oracle.getPrice(),
                targetRatio
            );

        // cap debt to repay based on sentinel calculation
        if (debtToRepay > actualDebtToRepay) {
            debtToRepay = actualDebtToRepay;
        }
        if (debtToRepay > pos.debtAmount) {
            debtToRepay = pos.debtAmount;
        }

        // recalculate collateral to seize based on actual debt repaid with liquidation bonus
        collateralToSeize = (debtToRepay * (100 + LIQUIDATION_BONUS) * 1e16) / oracle.getPrice();
        if (collateralToSeize > pos.collateralAmount) {
            collateralToSeize = pos.collateralAmount;
        }

        // execute liquidation
        debtToken.transferFrom(msg.sender, address(this), debtToRepay);
        pos.debtAmount -= debtToRepay;
        pos.collateralAmount -= collateralToSeize;
        collateralToken.transfer(msg.sender, collateralToSeize);

        // resolve soft liquidation if debt is fully repaid
        if (pos.debtAmount == 0) {
            sentinel.resolveSoftLiquidation(user);
        }

        emit Liquidated(user, msg.sender, debtToRepay, collateralToSeize);
    }

    /**
     * @notice Get position details.
     * @param user User address.
     * @return collateralAmount Collateral amount.
     * @return debtAmount Debt amount.
     * @return riskScore Risk score.
     * @return healthFactor Current health factor.
     * @return maxBorrow Maximum borrowable amount.
     */
    function getPositionDetails(address user) external view returns (
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 riskScore,
        uint256 healthFactor,
        uint256 maxBorrow
    ) {
        Position memory pos = positions[user];
        collateralAmount = pos.collateralAmount;
        debtAmount = pos.debtAmount;
        riskScore = pos.riskScore;
        healthFactor = getHealthFactor(user);
        maxBorrow = getMaxBorrowAmount(collateralAmount, riskScore);
    }

    /**
     * @notice Get current nonce for a user for ZK proof generation.
     * @param user User address.
     * @return Current nonce value for the user.
     */
    function getCurrentNonce(address user) external view returns (uint256) {
        return verifier.getCurrentNonce(user);
    }

    /**
     * @notice Get protocol constants for frontend integration.
     * @return proofValidityPeriod ZK proof validity period in seconds.
     * @return maxLiquidationRatio Maximum liquidation ratio percentage.
     * @return liquidationBonus Liquidation bonus percentage.
     * @return borrowCooldown Borrow cooldown period in seconds.
     * @return actionCooldown General action cooldown period in seconds.
     */
    function getProtocolConstants() external pure returns (
        uint256 proofValidityPeriod,
        uint256 maxLiquidationRatio,
        uint256 liquidationBonus,
        uint256 borrowCooldown,
        uint256 actionCooldown
    ) {
        return (
            PROOF_VALIDITY_PERIOD,
            MAX_LIQUIDATION_RATIO,
            LIQUIDATION_BONUS,
            BORROW_COOLDOWN,
            ACTION_COOLDOWN
        );
    }
}
