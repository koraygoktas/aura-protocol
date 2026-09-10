// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AuraSentinel
 * @notice Manages two-stage soft-liquidations and sentinel buffer.
 *         Protects users from getting instantly wiped out by external MEV bots.
 */
contract AuraSentinel {
    address public coreEngine;

    // Grace period for each user in soft liquidation (1 day)
    mapping(address => uint256) public gracePeriodEnd;
    mapping(address => bool) public inSoftLiquidation;

    event SoftLiquidationTriggered(address indexed user, uint256 gracePeriodEnd);
    event SoftLiquidationResolved(address indexed user);
    event LiquidationExecuted(
        address indexed user, 
        address indexed liquidator, 
        uint256 debtRepaid, 
        uint256 collateralRewarded, 
        bool isFull
    );

    modifier onlyCore() {
        require(msg.sender == coreEngine, "Sentinel: only Core Engine");
        _;
    }

    constructor(address _coreEngine) {
        coreEngine = _coreEngine;
    }

    /**
     * @notice Update the core engine address (only callable by current core engine).
     * @dev This allows for circular dependency resolution during deployment.
     */
    function setCoreEngine(address _newCoreEngine) external onlyCore {
        coreEngine = _newCoreEngine;
    }

    /**
     * @notice Calculate health factor of a borrowing position.
     * @dev Health factor = (Collateral Value * 1e18) / Required Collateral Value
     *      Where Required Collateral Value = Debt * Target Ratio
     * @return healthFactor Health factor scaled to 1e18 (>= 1e18 is healthy)
     */
    function calculateHealthFactor(
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 collateralPrice,
        uint256 targetRatio
    ) public pure returns (uint256 healthFactor) {
        if (debtAmount == 0) return type(uint256).max;
        
        // collateralValue = collateralAmount * collateralPrice / 1e18
        uint256 collateralValue = (collateralAmount * collateralPrice) / 1e18;
        
        // requiredCollateralValue = debtAmount * targetRatio / 1e18
        uint256 requiredCollateralValue = (debtAmount * targetRatio) / 1e18;
        
        if (requiredCollateralValue == 0) return type(uint256).max;
        
        return (collateralValue * 1e18) / requiredCollateralValue;
    }

    /**
     * @notice Process the logic for a liquidation.
     * @dev Called only by the Core Engine when someone initiates a liquidation.
     */
    function processLiquidation(
        address user,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 collateralPrice,
        uint256 targetRatio
    ) external onlyCore returns (
        uint256 debtToRepay,
        uint256 collateralToReward,
        bool isFullLiquidation
    ) {
        uint256 hf = calculateHealthFactor(collateralAmount, debtAmount, collateralPrice, targetRatio);
        require(hf < 1e18, "Sentinel: position is healthy");

        // Stage 1 vs Stage 2 determination
        if (!inSoftLiquidation[user]) {
            // First time liquidating -> Soft liquidation
            inSoftLiquidation[user] = true;
            gracePeriodEnd[user] = block.timestamp + 1 days;
            
            isFullLiquidation = false;
            // Max 50% debt can be repaid in soft liquidation
            debtToRepay = debtAmount / 2;
            if (debtToRepay == 0 && debtAmount > 0) {
                debtToRepay = debtAmount; // Handle dust
                isFullLiquidation = true;
            }
            
            // Soft liquidation incentive is 5% bonus
            // collateralToReward = (debtToRepay * 1.05 * 1e18) / collateralPrice
            collateralToReward = (debtToRepay * 105 * 1e16) / collateralPrice;
            
            emit SoftLiquidationTriggered(user, gracePeriodEnd[user]);
        } else {
            // Already in soft liquidation. Check if grace period has expired
            if (block.timestamp > gracePeriodEnd[user]) {
                // Stage 2: Grace period expired -> Full liquidation allowed
                isFullLiquidation = true;
                debtToRepay = debtAmount;
                
                // Full liquidation incentive is 10% bonus
                collateralToReward = (debtToRepay * 110 * 1e16) / collateralPrice;
            } else {
                // Grace period NOT expired. Only up to 50% of the remaining debt can be repaid
                // to act as soft-liquidation buffer, and cannot trigger another grace period extension.
                isFullLiquidation = false;
                debtToRepay = debtAmount / 2;
                if (debtToRepay == 0 && debtAmount > 0) {
                    debtToRepay = debtAmount;
                }
                collateralToReward = (debtToRepay * 105 * 1e16) / collateralPrice;
            }
        }

        // Bound collateral reward to prevent over-drawing contract
        if (collateralToReward > collateralAmount) {
            collateralToReward = collateralAmount;
        }

        // If debt is fully paid off, reset liquidation status
        if (debtAmount <= debtToRepay) {
            inSoftLiquidation[user] = false;
            gracePeriodEnd[user] = 0;
        }
    }

    /**
     * @notice Resets soft liquidation state when user restores health.
     */
    function resolveSoftLiquidation(address user) external onlyCore {
        if (inSoftLiquidation[user]) {
            inSoftLiquidation[user] = false;
            gracePeriodEnd[user] = 0;
            emit SoftLiquidationResolved(user);
        }
    }
}
