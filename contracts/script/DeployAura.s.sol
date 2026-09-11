// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {AuraVerifier} from "../src/AuraVerifier.sol";
import {AuraSentinel} from "../src/AuraSentinel.sol";
import {AuraCoreEngine} from "../src/AuraCoreEngine.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";

contract DeployAura is Script {
    AuraVerifier public verifier;
    AuraSentinel public sentinel;
    AuraCoreEngine public engine;
    MockERC20 public collateralToken;
    MockERC20 public debtToken;
    MockOracle public oracle;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy AuraVerifier
        verifier = new AuraVerifier();
        console2.log("AuraVerifier deployed at:", address(verifier));

        // 2. Deploy Mock Oracle with initial price (1e18 = 1:1 ratio)
        oracle = new MockOracle(1e18);
        console2.log("MockOracle deployed at:", address(oracle));

        // 3. Deploy Mock Collateral Token
        collateralToken = new MockERC20("Mock Collateral", "mCOLL");
        console2.log("Mock Collateral Token deployed at:", address(collateralToken));

        // 4. Deploy Mock Debt Token
        debtToken = new MockERC20("Mock Debt", "mDEBT");
        console2.log("Mock Debt Token deployed at:", address(debtToken));

        // 5. Deploy AuraSentinel with temporary address (circular dependency resolution)
        sentinel = new AuraSentinel(deployer);
        console2.log("AuraSentinel deployed at:", address(sentinel));

        // 6. Deploy AuraCoreEngine with all dependencies
        engine = new AuraCoreEngine(
            address(sentinel),
            address(verifier),
            address(collateralToken),
            address(debtToken),
            address(oracle)
        );
        console2.log("AuraCoreEngine deployed at:", address(engine));

        // 7. Update Sentinel to point to actual Engine address
        sentinel.setCoreEngine(address(engine));
        console2.log("AuraSentinel coreEngine updated to:", address(engine));

        // 8. Mint initial tokens to deployer
        uint256 initialSupply = 1_000_000 * 1e18; // 1 million tokens
        
        collateralToken.mint(deployer, initialSupply);
        console2.log("Minted", initialSupply / 1e18, "mCOLL to deployer:", deployer);

        debtToken.mint(deployer, initialSupply);
        console2.log("Minted", initialSupply / 1e18, "mDEBT to deployer:", deployer);

        // 9. Mint debt tokens to engine for lending
        uint256 lendingPool = 10_000_000 * 1e18; // 10 million tokens for lending
        debtToken.mint(address(engine), lendingPool);
        console2.log("Minted", lendingPool / 1e18, "mDEBT to AuraCoreEngine for lending");

        vm.stopBroadcast();

        console2.log("\n=== Deployment Summary ===");
        console2.log("Deployer:", deployer);
        console2.log("AuraVerifier:", address(verifier));
        console2.log("AuraSentinel:", address(sentinel));
        console2.log("AuraCoreEngine:", address(engine));
        console2.log("Mock Collateral (mCOLL):", address(collateralToken));
        console2.log("Mock Debt (mDEBT):", address(debtToken));
        console2.log("MockOracle:", address(oracle));
    }
}
