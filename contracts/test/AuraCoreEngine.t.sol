// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AuraCoreEngine.sol";
import "../src/AuraSentinel.sol";
import "../src/AuraVerifier.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockOracle.sol";

contract AuraCoreEngineTest is Test {
    AuraCoreEngine public engine;
    AuraSentinel public sentinel;
    AuraVerifier public verifier;
    MockERC20 public collateralToken;
    MockERC20 public debtToken;
    MockOracle public oracle;

    address public user1;
    address public user2;
    address public liquidator;

    function setUp() public {
        // Deploy mock contracts
        collateralToken = new MockERC20("Collateral Token", "COLL");
        debtToken = new MockERC20("Debt Token", "DEBT");
        oracle = new MockOracle(1e18); // 1:1 price ratio initially
        verifier = new AuraVerifier();
        
        // Deploy sentinel with temporary address (circular dependency resolution)
        sentinel = new AuraSentinel(address(this)); // Use test contract as temporary

        // Deploy engine with sentinel
        engine = new AuraCoreEngine(
            address(sentinel),
            address(verifier),
            address(collateralToken),
            address(debtToken),
            address(oracle)
        );

        // Update sentinel to point to actual engine
        sentinel.setCoreEngine(address(engine));

        // Setup users
        user1 = address(0x1);
        user2 = address(0x2);
        liquidator = address(0x3);

        // Mint tokens for users
        collateralToken.mint(user1, 1000e18);
        collateralToken.mint(user2, 1000e18);
        collateralToken.mint(liquidator, 1000e18);
        
        debtToken.mint(address(engine), 10000e18); // Engine needs debt tokens to lend
        debtToken.mint(liquidator, 1000e18); // Liquidator needs debt tokens to repay
    }

    function test_Deposit() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);
        vm.stopPrank();

        (uint256 collateralAmount,,,,) = engine.getPositionDetails(user1);
        assertEq(collateralAmount, 100e18);
    }

    function test_Depmit_ZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert(AuraCoreEngine.ZeroAmount.selector);
        engine.deposit(0);
        vm.stopPrank();
    }

    function test_Borrow_WithZK() public {
        // Deposit collateral first
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown
        skip(6 minutes);

        // Prepare ZK proof (mock valid proof)
        bytes memory proof = abi.encodePacked("valid-proof");
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = uint256(uint160(user1));
        publicInputs[1] = 25; // Risk score 25 (tier 1, 90% LTV)

        // Get current nonce for user
        uint256 currentNonce = verifier.getCurrentNonce(user1);
        uint256 validUntil = block.timestamp + 1 hours; // Valid for 1 hour

        // Borrow with new parameters
        engine.borrowWithZK(50e18, proof, publicInputs, validUntil, currentNonce);
        vm.stopPrank();

        (, uint256 debtAmount, uint256 riskScore,,) = engine.getPositionDetails(user1);
        assertEq(debtAmount, 50e18);
        assertEq(riskScore, 25);
        
        // Verify nonce was incremented
        assertEq(verifier.getCurrentNonce(user1), currentNonce + 1);
    }

    function test_Borrow_WithoutZK() public {
        // Deposit collateral first
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown
        skip(6 minutes);

        // Borrow without ZK (for testing)
        engine.borrow(50e18, 25); // Risk score 25
        vm.stopPrank();

        (, uint256 debtAmount, uint256 riskScore,,) = engine.getPositionDetails(user1);
        assertEq(debtAmount, 50e18);
        assertEq(riskScore, 25);
    }

    function test_Borrow_ExceedsMaxBorrow() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown
        skip(6 minutes);

        // Try to borrow more than max (90% of 100 = 90)
        vm.expectRevert(AuraCoreEngine.InsufficientCollateral.selector);
        engine.borrow(95e18, 25);
        vm.stopPrank();
    }

    function test_Borrow_InvalidProof() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown
        skip(6 minutes);

        bytes memory invalidProof = abi.encodePacked("invalid-proof");
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = uint256(uint160(user1));
        publicInputs[1] = 25;

        uint256 currentNonce = verifier.getCurrentNonce(user1);
        uint256 validUntil = block.timestamp + 1 hours;

        vm.expectRevert(AuraCoreEngine.InvalidProof.selector);
        engine.borrowWithZK(50e18, invalidProof, publicInputs, validUntil, currentNonce);
        vm.stopPrank();
    }

    function test_Borrow_Cooldown() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown for first borrow
        skip(6 minutes);
        engine.borrow(50e18, 25);

        // Try to borrow again immediately (within cooldown)
        vm.expectRevert(AuraCoreEngine.CooldownNotMet.selector);
        engine.borrow(10e18, 25);
        vm.stopPrank();
    }

    function test_Borrow_ExpiredProof() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Underflow olmamasi icin once zamani ileri sar
        skip(1000);

        bytes memory proof = abi.encodePacked("valid-proof");
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = uint256(uint160(user1));
        publicInputs[1] = 25;

        uint256 currentNonce = verifier.getCurrentNonce(user1);
        uint256 validUntil = block.timestamp - 1; // Suresi gecmis

        vm.expectRevert(AuraVerifier.ProofExpired.selector);
        engine.borrowWithZK(50e18, proof, publicInputs, validUntil, currentNonce);
        vm.stopPrank();
    }

    function test_Borrow_InvalidNonce() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown
        skip(6 minutes);

        bytes memory proof = abi.encodePacked("valid-proof");
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = uint256(uint160(user1));
        publicInputs[1] = 25;

        uint256 invalidNonce = 999; // Wrong nonce
        uint256 validUntil = block.timestamp + 1 hours;

        vm.expectRevert(AuraVerifier.InvalidNonce.selector);
        engine.borrowWithZK(50e18, proof, publicInputs, validUntil, invalidNonce);
        vm.stopPrank();
    }

    function test_Borrow_ProofReplay() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown
        skip(6 minutes);

        bytes memory proof = abi.encodePacked("valid-proof");
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = uint256(uint160(user1));
        publicInputs[1] = 25;

        uint256 currentNonce = verifier.getCurrentNonce(user1);
        uint256 validUntil = block.timestamp + 1 hours;

        // First borrow - should succeed
        engine.borrowWithZK(30e18, proof, publicInputs, validUntil, currentNonce);

        // Flash loan cooldown'u atla
        skip(6 minutes);

        // Ayni nonce/proof ile tekrar denenince revert etmeli
        vm.expectRevert(AuraVerifier.InvalidNonce.selector);
        engine.borrowWithZK(20e18, proof, publicInputs, validUntil, currentNonce);
        vm.stopPrank();
    }

    function test_Borrow_InvalidProofBinding() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown
        skip(6 minutes);

        bytes memory proof = abi.encodePacked("valid-proof");
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = uint256(uint160(address(0x999))); // Wrong address binding
        publicInputs[1] = 25;

        uint256 currentNonce = verifier.getCurrentNonce(user1);
        uint256 validUntil = block.timestamp + 1 hours;

        vm.expectRevert(AuraVerifier.InvalidProofBinding.selector);
        engine.borrowWithZK(50e18, proof, publicInputs, validUntil, currentNonce);
        vm.stopPrank();
    }

    function test_Repay() public {
        // Setup: deposit and borrow
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown for borrow
        skip(6 minutes);
        engine.borrow(50e18, 25);

        // Repay
        debtToken.approve(address(engine), 30e18);
        engine.repay(30e18);
        vm.stopPrank();

        (, uint256 debtAmount,,,) = engine.getPositionDetails(user1);
        assertEq(debtAmount, 20e18);
    }

    function test_Repay_FullRepay() public {
        // Setup: deposit and borrow
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown for borrow
        skip(6 minutes);
        engine.borrow(50e18, 25);

        // Repay full amount
        debtToken.approve(address(engine), 100e18);
        engine.repay(100e18);
        vm.stopPrank();

        (, uint256 debtAmount,,,) = engine.getPositionDetails(user1);
        assertEq(debtAmount, 0);
    }

    function test_Withdraw() public {
        // Setup: deposit
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown
        skip(2 minutes);

        // Withdraw
        engine.withdraw(30e18);
        vm.stopPrank();

        (uint256 collateralAmount,,,,) = engine.getPositionDetails(user1);
        assertEq(collateralAmount, 70e18);
    }

    function test_Withdraw_UnhealthyPosition() public {
        // Setup: deposit and borrow
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown for borrow
        skip(6 minutes);
        engine.borrow(80e18, 25);

        // Skip cooldown for withdraw
        skip(2 minutes);

        // Try to withdraw - should fail due to unhealthy position
        vm.expectRevert(AuraCoreEngine.InsufficientCollateral.selector);
        engine.withdraw(50e18);
        vm.stopPrank();
    }

    function test_Withdraw_Cooldown() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Try to withdraw immediately (within cooldown)
        vm.expectRevert(AuraCoreEngine.CooldownNotMet.selector);
        engine.withdraw(30e18);
        vm.stopPrank();
    }

    function test_Liquidation_SoftLiquidation() public {
        // Setup: user1 deposits and borrows
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown for borrow
        skip(6 minutes);
        engine.borrow(80e18, 25);
        vm.stopPrank();

        // Drop price to make position unhealthy
        oracle.setPrice(0.8e18); // 20% price drop

        // Liquidate
        vm.startPrank(liquidator);
        debtToken.approve(address(engine), 40e18);
        engine.liquidate(user1, 40e18);
        vm.stopPrank();

        (uint256 collateralAmount, uint256 debtAmount,,,) = engine.getPositionDetails(user1);
        // Should be in soft liquidation, max 50% debt repaid
        assertLt(debtAmount, 80e18);
        assertGt(debtAmount, 0);
        assertLt(collateralAmount, 100e18);
    }

    function test_Liquidation_FullLiquidation() public {
        // Setup: user1 deposits and borrows
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown for borrow
        skip(6 minutes);
        engine.borrow(80e18, 25);
        vm.stopPrank();

        // Drop price to make position extremely unhealthy
        oracle.setPrice(0.3e18); // 70% price drop

        // First liquidation (soft liquidation - max %50 odenir: 40e18)
        vm.startPrank(liquidator);
        debtToken.approve(address(engine), 100e18);
        engine.liquidate(user1, 40e18);
        vm.stopPrank();

        (uint256 collateralAmount, uint256 debtAmount,,,) = engine.getPositionDetails(user1);
        assertGt(debtAmount, 0);
        assertLt(debtAmount, 80e18);

        // Wait for grace period to expire (1 day)
        skip(1 days + 1);

        // Second liquidation (kalan 40e18 borcun %50'si = 20e18 odenir)
        vm.startPrank(liquidator);
        debtToken.approve(address(engine), 100e18);
        engine.liquidate(user1, debtAmount);
        vm.stopPrank();

        (collateralAmount, debtAmount,,,) = engine.getPositionDetails(user1);
        // MAX_LIQUIDATION_RATIO = 50 oldugu icin borc 20e18 kalmalidir
        assertEq(debtAmount, 20e18);
        assertLt(collateralAmount, 100e18);
    }

    function test_Liquidation_HealthyPosition() public {
        // Setup: user1 deposits and borrows (healthy position)
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown for borrow
        skip(6 minutes);
        engine.borrow(50e18, 25);
        vm.stopPrank();

        // Try to liquidate healthy position
        vm.startPrank(liquidator);
        debtToken.approve(address(engine), 10e18);
        vm.expectRevert(AuraCoreEngine.PositionHealthy.selector);
        engine.liquidate(user1, 10e18);
        vm.stopPrank();
    }

    function test_DynamicLTV_Tier1() public view {
        uint256 ltv = engine.getDynamicLTV(25);
        assertEq(ltv, 90); // 90% for risk score 0-25
    }

    function test_DynamicLTV_Tier2() public view {
        uint256 ltv = engine.getDynamicLTV(50);
        assertEq(ltv, 75); // 75% for risk score 26-50
    }

    function test_DynamicLTV_Tier3() public view {
        uint256 ltv = engine.getDynamicLTV(75);
        assertEq(ltv, 60); // 60% for risk score 51-75
    }

    function test_DynamicLTV_Tier4() public view {
        uint256 ltv = engine.getDynamicLTV(100);
        assertEq(ltv, 45); // 45% for risk score 76-100
    }

    function test_GetMaxBorrowAmount() public view {
        uint256 maxBorrow = engine.getMaxBorrowAmount(100e18, 25);
        // 100 collateral * 1 price * 90% LTV = 90
        assertEq(maxBorrow, 90e18);
    }

    function test_GetHealthFactor_Healthy() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown for borrow
        skip(6 minutes);
        engine.borrow(50e18, 25);
        vm.stopPrank();

        uint256 hf = engine.getHealthFactor(user1);
        assertGe(hf, 1e18); // Should be healthy
    }

    function test_GetHealthFactor_Unhealthy() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown for borrow
        skip(6 minutes);
        engine.borrow(80e18, 25);
        vm.stopPrank();

        // Drop price
        oracle.setPrice(0.8e18);

        uint256 hf = engine.getHealthFactor(user1);
        assertLt(hf, 1e18); // Should be unhealthy
    }

    function test_GetHealthFactor_NoDebt() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);
        vm.stopPrank();

        uint256 hf = engine.getHealthFactor(user1);
        assertEq(hf, type(uint256).max); // Max when no debt
    }

    function test_GetPositionDetails() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown for borrow
        skip(6 minutes);
        engine.borrow(50e18, 25);
        vm.stopPrank();

        (
            uint256 collateralAmount,
            uint256 debtAmount,
            uint256 riskScore,
            uint256 healthFactor,
            uint256 maxBorrow
        ) = engine.getPositionDetails(user1);

        assertEq(collateralAmount, 100e18);
        assertEq(debtAmount, 50e18);
        assertEq(riskScore, 25);
        assertGe(healthFactor, 1e18);
        assertEq(maxBorrow, 90e18);
    }

    function test_RiskScoreUpdate() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown for first borrow
        skip(6 minutes);
        engine.borrow(50e18, 25);

        // Skip cooldown for second borrow
        skip(10 minutes);

        // Borrow with different risk score
        engine.borrow(10e18, 50);
        vm.stopPrank();

        (, , uint256 riskScore, , ) = engine.getPositionDetails(user1);
        assertEq(riskScore, 50);
    }

    function test_AntiFlashLoan_BorrowCooldown() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown for first borrow
        skip(6 minutes);
        engine.borrow(40e18, 25);

        // Try to borrow again within cooldown (5 minutes)
        vm.expectRevert(AuraCoreEngine.CooldownNotMet.selector);
        engine.borrow(10e18, 25);
        vm.stopPrank();
    }

    function test_AntiFlashLoan_WithdrawCooldown() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Try to withdraw within cooldown (1 minute)
        vm.expectRevert(AuraCoreEngine.CooldownNotMet.selector);
        engine.withdraw(10e18);
        vm.stopPrank();
    }

    function test_BorrowAfterCooldown() public {
        vm.startPrank(user1);
        collateralToken.approve(address(engine), 100e18);
        engine.deposit(100e18);

        // Skip cooldown for first borrow
        skip(6 minutes);
        engine.borrow(40e18, 25);

        // Wait for cooldown to expire
        skip(6 minutes);

        // Should succeed now
        engine.borrow(10e18, 25);
        vm.stopPrank();

        (, uint256 debtAmount, , , ) = engine.getPositionDetails(user1);
        assertEq(debtAmount, 50e18);
    }
}
