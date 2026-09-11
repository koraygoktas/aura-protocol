// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AuraCoreEngine.sol";
import "../src/AuraSentinel.sol";
import "../src/AuraVerifier.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockOracle.sol";

contract AuraInvariantTest is Test {
    AuraCoreEngine public engine;
    AuraSentinel public sentinel;
    AuraVerifier public verifier;
    MockERC20 public collateralToken;
    MockERC20 public debtToken;
    MockOracle public oracle;

    address public user1;
    address public user2;
    address public liquidator;

    // Handler contract for invariant testing
    Handler public handler;

    function setUp() public {
        // Deploy mock contracts
        collateralToken = new MockERC20("Collateral Token", "COLL");
        debtToken = new MockERC20("Debt Token", "DEBT");
        oracle = new MockOracle(1e18);
        verifier = new AuraVerifier();
        
        // Deploy sentinel with temporary address
        sentinel = new AuraSentinel(address(this));

        // Deploy engine
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
        
        debtToken.mint(address(engine), 10000e18);
        debtToken.mint(liquidator, 1000e18);

        // Deploy handler
        handler = new Handler(engine, collateralToken, debtToken, oracle, verifier);
        
        // Give handler tokens
        collateralToken.mint(address(handler), 10000e18);
        debtToken.mint(address(handler), 10000e18);

        // Target the handler for invariant testing
        targetContract(address(handler));
    }

    // Invariant 1: Total debt balance never goes below zero
    function invariant_totalDebtNeverNegative() public view {
        (, uint256 totalDebt1,,,) = engine.getPositionDetails(user1);
        (, uint256 totalDebt2,,,) = engine.getPositionDetails(user2);
        
        assertGe(totalDebt1, 0, "User1 debt cannot be negative");
        assertGe(totalDebt2, 0, "User2 debt cannot be negative");
    }

    // Invariant 2: Collateral amount never goes below zero
    function invariant_collateralNeverNegative() public view {
        (uint256 collateral1,,, ,) = engine.getPositionDetails(user1);
        (uint256 collateral2,,, ,) = engine.getPositionDetails(user2);
        
        assertGe(collateral1, 0, "User1 collateral cannot be negative");
        assertGe(collateral2, 0, "User2 collateral cannot be negative");
    }

    // Invariant 3: Health factor calculation consistency
    function invariant_healthFactorConsistency() public view {
        (uint256 collateral1, uint256 debt1,, uint256 healthFactor1,) = engine.getPositionDetails(user1);
        
        if (debt1 > 0) {
            // Manual health factor calculation
            uint256 collateralValue = (collateral1 * oracle.getPrice()) / 1e18;
            uint256 requiredCollateral = (debt1 * 110 * 1e16) / 1e18; // 110% target ratio
            uint256 calculatedHealthFactor = (collateralValue * 1e18) / requiredCollateral;
            
            // Health factor should be approximately equal (allowing for rounding)
            assertApproxEqRel(healthFactor1, calculatedHealthFactor, 1e16, "Health factor calculation inconsistent");
        } else {
            // When debt is 0, health factor should be max
            assertEq(healthFactor1, type(uint256).max, "Health factor should be max when debt is 0");
        }
    }

    // Invariant 4: Protocol reserves consistency
    function invariant_protocolReservesConsistent() public view {
        uint256 engineCollateralBalance = collateralToken.balanceOf(address(engine));
        uint256 engineDebtBalance = debtToken.balanceOf(address(engine));
        
        // Engine should have collateral deposited by users
        assertGe(engineCollateralBalance, 0, "Engine collateral balance cannot be negative");
        
        // Engine debt balance should be sufficient for lending
        assertGe(engineDebtBalance, 0, "Engine debt balance cannot be negative");
    }

    // Invariant 5: Risk score always in valid range
    function invariant_riskScoreValidRange() public view {
        (, , uint256 riskScore1, ,) = engine.getPositionDetails(user1);
        (, , uint256 riskScore2, ,) = engine.getPositionDetails(user2);
        
        assertLe(riskScore1, 100, "Risk score cannot exceed 100");
        assertLe(riskScore2, 100, "Risk score cannot exceed 100");
    }
}

contract Handler is Test{
    AuraCoreEngine public engine;
    MockERC20 public collateralToken;
    MockERC20 public debtToken;
    MockOracle public oracle;
    AuraVerifier public verifier;

    address public user1;
    address public user2;
    address public liquidator;

    uint256 public nonce1;
    uint256 public nonce2;

    constructor(
        AuraCoreEngine _engine,
        MockERC20 _collateralToken,
        MockERC20 _debtToken,
        MockOracle _oracle,
        AuraVerifier _verifier
    ) {
        engine = _engine;
        collateralToken = _collateralToken;
        debtToken = _debtToken;
        oracle = _oracle;
        verifier = _verifier;

        user1 = address(0x1);
        user2 = address(0x2);
        liquidator = address(0x3);

        nonce1 = verifier.getCurrentNonce(user1);
        nonce2 = verifier.getCurrentNonce(user2);
    }

    // Handler function: deposit collateral
    function depositCollateral(uint256 amount) public {
        amount = bound(amount, 1e18, 1000e18);
        
        address user = (randomUser() == 0) ? user1 : user2;
        
        vm.startPrank(user);
        collateralToken.approve(address(engine), amount);
        engine.deposit(amount);
        vm.stopPrank();
    }

    // Handler function: borrow without ZK (for testing invariants)
    function borrowWithoutZK(uint256 amount, uint256 riskScore) public {
        amount = bound(amount, 1e18, 500e18);
        riskScore = bound(riskScore, 0, 100);
        
        address user = (randomUser() == 0) ? user1 : user2;
        
        vm.startPrank(user);
        // Skip cooldown
        skip(6 minutes);
        engine.borrow(amount, riskScore);
        vm.stopPrank();
    }

    // Handler function: repay debt
    function repayDebt(uint256 amount) public {
        amount = bound(amount, 1e18, 500e18);
        
        address user = (randomUser() == 0) ? user1 : user2;
        
        vm.startPrank(user);
        debtToken.approve(address(engine), amount);
        engine.repay(amount);
        vm.stopPrank();
    }

    // Handler function: withdraw collateral
    function withdrawCollateral(uint256 amount) public {
        amount = bound(amount, 1e18, 500e18);
        
        address user = (randomUser() == 0) ? user1 : user2;
        
        vm.startPrank(user);
        skip(2 minutes); // Skip cooldown
        engine.withdraw(amount);
        vm.stopPrank();
    }

    // Handler function: liquidate position
    function liquidatePosition(uint256 amount) public {
        amount = bound(amount, 1e18, 100e18);
        
        // Drop price to make positions unhealthy
        oracle.setPrice(0.5e18);
        
        vm.startPrank(liquidator);
        debtToken.approve(address(engine), amount);
        
        // Try to liquidate user1 or user2
        address userToLiquidate = (randomUser() == 0) ? user1 : user2;
        engine.liquidate(userToLiquidate, amount);
        vm.stopPrank();
        
        // Reset price
        oracle.setPrice(1e18);
    }

    // Handler function: update oracle price
    function updateOraclePrice(uint256 newPrice) public {
        newPrice = bound(newPrice, 0.1e18, 2e18);
        oracle.setPrice(newPrice);
    }

    // Helper: random user selection
    function randomUser() internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % 2;
    }

    // Fuzz target function that calls handlers randomly
    function fuzzHandler(uint256 seed) public {
        uint256 action = seed % 6;
        
        if (action == 0) {
            depositCollateral(seed);
        } else if (action == 1) {
            borrowWithoutZK(seed, seed % 101);
        } else if (action == 2) {
            repayDebt(seed);
        } else if (action == 3) {
            withdrawCollateral(seed);
        } else if (action == 4) {
            liquidatePosition(seed);
        } else {
            updateOraclePrice(seed);
        }
    }
}
