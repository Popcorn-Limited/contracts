// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

import {MockERC4626} from "../utils/mocks/MockERC4626.sol";

import {MultiStrategyVault} from "src/vaults/MultiStrategyVault.sol";
import {AaveV3Depositor, IERC20} from "src/strategies/aave/aaveV3/AaveV3Depositor.sol";

struct TestConfig {
    address asset;
    uint256 blockNumber;
    uint256 defaultAmount;
    uint256 delta;
    uint256 maxDeposit;
    uint256 maxWithdraw;
    uint256 minDeposit;
    uint256 minWithdraw;
    string network;
    IERC4626[] strategies;
    string testId;
}

/**
 * This test is used to test a Vault + Strategy combination.
 * Before you deploy a vault, add the Vault, Strategy, and asset you're going to use to this
 * test and it will run all kinds of integration tests to verify that everything works as expected
 */
contract DeploymentTest is Test {
    using stdJson for string;

    string internal json;
    uint256 internal configLength;

    TestConfig internal testConfig;
    // only works with MultiStrategyVault for now
    MultiStrategyVault vault;
    IERC20 asset;

    address alice = address(0xABCD);
    address bob = address(0xDCBA);

    // should be called with index (0, configLength] in every test function
    // through a for loop
    function _setUpTest(uint256 index) internal {
        testConfig = abi.decode(json.parseRaw(string.concat(".configs[", vm.toString(index), "]")), (TestConfig));
        asset = IERC20(testConfig.asset);

        // Setup fork environment
        testConfig.blockNumber > 0
            ? vm.createSelectFork(vm.rpcUrl(testConfig.network), testConfig.blockNumber)
            : vm.createSelectFork(vm.rpcUrl(testConfig.network));

        address implementation = address(new MultiStrategyVault());
        vault = MultiStrategyVault(Clones.clone(implementation));

        uint256[] memory withdrawalQueue = new uint256[](1);

        vault.initialize(IERC20(asset), testConfig.strategies, uint256(0), withdrawalQueue, type(uint256).max, address(this));

        vm.label(address(vault), "vault");
        vm.label(address(asset), "asset");
    }

    function _createMockStrategy(IERC20 _asset) internal returns (IERC4626) {
        address strategyImplementation = address(new MockERC4626());
        address strategyAddress = Clones.clone(strategyImplementation);
        MockERC4626(strategyAddress).initialize(_asset, "Mock Token Vault", "vwTKN");
        return IERC4626(strategyAddress);
    }

    function setUp() public {
        json = vm.readFile("./test/integration/DeploymentTestConfig.json");
        configLength = json.readUint(".length");
    }

    function test__deposit_withdraw(uint128 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, 100_000e18);
        for (uint256 i; i < configLength; ++i) {
            _setUpTest(i);

            deal(address(asset), alice, amount);

            vm.prank(alice);
            asset.approve(address(vault), amount);
            assertEq(asset.allowance(alice, address(vault)), amount);

            uint256 alicePreDepositBal = asset.balanceOf(alice);

            vm.prank(alice);
            uint256 shares = vault.deposit(amount, alice);

            assertEq(amount, shares);
            assertApproxEqAbs(
                vault.previewWithdraw(amount), shares, testConfig.delta, "previewWithdraw should match share amount"
            );
            assertApproxEqAbs(
                vault.previewDeposit(amount), shares, testConfig.delta, "previewDeposit should match share amount"
            );
            assertApproxEqAbs(
                vault.totalSupply(), shares, testConfig.delta, "totalSupply should be equal to minted shares"
            );
            assertApproxEqAbs(
                vault.totalAssets(), amount, testConfig.delta, "totalAssets should be equal to deposited amount"
            );
            assertApproxEqAbs(
                vault.balanceOf(alice), shares, testConfig.delta, "alice should own all the minted vault shares"
            );
            assertApproxEqAbs(
                vault.convertToAssets(vault.balanceOf(alice)),
                amount,
                testConfig.delta,
                "minted shares should be convertable to deposited amount of assets"
            );
            assertApproxEqAbs(
                asset.balanceOf(alice),
                alicePreDepositBal - amount,
                testConfig.delta,
                "should have transferred assets from alice to vault"
            );

            uint256 withdrawAmount = vault.maxWithdraw(alice);
            vm.prank(alice);
            vault.withdraw(withdrawAmount, alice, alice);

            assertEq(vault.totalAssets(), 0);
            assertEq(vault.balanceOf(alice), 0);
            assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
            assertApproxEqAbs(
                asset.balanceOf(alice),
                alicePreDepositBal,
                testConfig.delta,
                "should should have same amount of assets after withdrawal"
            );
        }
    }

    function test__mint_redeem() public {
        uint256 amount = 1e18;
        amount = bound(amount, 1, 100_000e18);
        for (uint256 i; i < configLength; ++i) {
            _setUpTest(i);

            deal(address(asset), alice, amount);

            vm.prank(alice);
            asset.approve(address(vault), amount);
            assertEq(asset.allowance(alice, address(vault)), amount);

            uint256 alicePreDepositBal = asset.balanceOf(alice);

            vm.prank(alice);
            uint256 aliceAssetAmount = vault.mint(amount, alice);

            // Expect exchange rate to be 1:1 on initial mint.
            assertApproxEqAbs(amount, aliceAssetAmount, 1, "share = assets");
            assertApproxEqAbs(vault.previewWithdraw(aliceAssetAmount), amount, 1, "pw");
            assertApproxEqAbs(vault.previewDeposit(aliceAssetAmount), amount, 1, "pd");
            assertEq(vault.totalSupply(), amount, "ts");
            assertApproxEqAbs(vault.totalAssets(), aliceAssetAmount, testConfig.delta, "ta");
            assertEq(vault.balanceOf(alice), amount, "bal");
            assertApproxEqAbs(vault.convertToAssets(vault.balanceOf(alice)), aliceAssetAmount, 1, "convert");
            assertEq(asset.balanceOf(alice), alicePreDepositBal - aliceAssetAmount, "a bal");

            uint256 redeemAmount = vault.maxRedeem(alice);
            vm.prank(alice);
            vault.redeem(redeemAmount, alice, alice);

            assertApproxEqAbs(vault.totalAssets(), 0, 1);
            assertEq(vault.balanceOf(alice), 0);
            assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
            assertApproxEqAbs(asset.balanceOf(alice), alicePreDepositBal, 1);
        }
    }

    function test__interactions_for_someone_else() public {
        for (uint256 i; i < configLength; ++i) {
            _setUpTest(i);

            // init 2 users with a 1e18 balance
            deal(address(asset), alice, 1e18);
            deal(address(asset), bob, 1e18);

            vm.prank(alice);
            asset.approve(address(vault), 1e18);

            vm.prank(bob);
            asset.approve(address(vault), 1e18);

            // alice deposits 1e18 for bob
            vm.prank(alice);
            vault.deposit(1e18, bob);

            assertEq(vault.balanceOf(alice), 0);
            assertEq(vault.balanceOf(bob), 1e18);
            assertEq(asset.balanceOf(alice), 0);

            // bob mint 1e18 for alice
            vm.prank(bob);
            vault.mint(1e18, alice);
            assertEq(vault.balanceOf(alice), 1e18);
            assertEq(vault.balanceOf(bob), 1e18);
            assertEq(asset.balanceOf(bob), 0);

            // alice redeem 1e18 for bob
            vm.prank(alice);
            vault.redeem(1e18, bob, alice);

            assertEq(vault.balanceOf(alice), 0);
            assertEq(vault.balanceOf(bob), 1e18);
            assertApproxEqAbs(asset.balanceOf(bob), 1e18, testConfig.delta);

            // bob withdraw 1e18 for alice
            vm.prank(bob);
            vault.withdraw(1e18, alice, bob);

            assertEq(vault.balanceOf(alice), 0);
            assertEq(vault.balanceOf(bob), 0);
            assertApproxEqAbs(asset.balanceOf(alice), 1e18, testConfig.delta);
        }
    }

    function test__changeStrategies() public {
        for (uint256 i; i < configLength; ++i) {
            _setUpTest(i);

            IERC4626[] memory newStrategies = new IERC4626[](1);
            IERC4626 newStrategy = _createMockStrategy(IERC20(address(asset)));
            newStrategies[0] = newStrategy;

            uint256[] memory newWithdrawalQueue = new uint256[](1);
            newWithdrawalQueue[0] = uint256(0);

            uint256 depositAmount = 1 ether;

            // Deposit funds for testing
            deal(address(asset), alice, depositAmount);
            vm.startPrank(alice);
            asset.approve(address(vault), depositAmount);
            vault.deposit(depositAmount, alice);
            vm.stopPrank();

            address oldStrategy = address(vault.strategies(0));

            // Preparation to change the strategies
            vault.proposeStrategies(newStrategies, newWithdrawalQueue, uint256(0));

            vm.warp(block.timestamp + 3 days);

            vault.changeStrategies();

            assertEq(asset.allowance(address(vault), oldStrategy), 0);

            // Annoyingly Math fails us here and leaves 1 asset in the adapter
            assertEq(asset.balanceOf(address(vault.strategies(0))), 0);

            assertEq(vault.strategies(0).balanceOf(address(vault)), 0);

            assertEq(asset.balanceOf(address(newStrategy)), 0);
            assertGe(asset.balanceOf(address(vault)), depositAmount);
            assertEq(asset.allowance(address(vault), address(newStrategy)), type(uint256).max);

            IERC4626[] memory changedStrategies = vault.getStrategies();
            uint256[] memory changedWithdrawalQueue = vault.getWithdrawalQueue();

            assertEq(changedStrategies.length, 1);
            assertEq(address(changedStrategies[0]), address(newStrategy));

            assertEq(changedWithdrawalQueue.length, 1);
            assertEq(changedWithdrawalQueue[0], uint256(0));

            assertEq(vault.depositIndex(), 0);

            assertEq(vault.getProposedStrategies().length, 0);
            assertEq(vault.getProposedWithdrawalQueue().length, 0);
            assertEq(vault.proposedDepositIndex(), 0);
            assertEq(vault.proposedStrategyTime(), 0);
        }
    }

    function test__changeStrategies_to_no_strategies() public {
        for (uint256 i; i < configLength; ++i) {
            _setUpTest(i);

            IERC4626[] memory newStrategies;

            uint256[] memory newWithdrawalQueue;

            uint256 depositAmount = 1 ether;

            // Deposit funds for testing
            deal(address(asset), alice, depositAmount);
            vm.startPrank(alice);
            asset.approve(address(vault), depositAmount);
            vault.deposit(depositAmount, alice);
            vm.stopPrank();

            address oldStrategy = address(vault.strategies(0));

            // Preparation to change the strategies
            vault.proposeStrategies(newStrategies, newWithdrawalQueue, type(uint256).max);

            vm.warp(block.timestamp + 3 days);

            vault.changeStrategies();

            assertEq(asset.allowance(address(vault), oldStrategy), 0);

            assertEq(IERC4626(oldStrategy).balanceOf(address(vault)), 0);

            assertGe(asset.balanceOf(address(vault)), depositAmount);

            IERC4626[] memory changedStrategies = vault.getStrategies();
            uint256[] memory changedWithdrawalQueue = vault.getWithdrawalQueue();

            assertEq(changedStrategies.length, 0);
            assertEq(changedWithdrawalQueue.length, 0);
            assertEq(vault.depositIndex(), type(uint256).max);

            assertEq(vault.getProposedStrategies().length, 0);
            assertEq(vault.getProposedWithdrawalQueue().length, 0);
            assertEq(vault.proposedDepositIndex(), 0);
            assertEq(vault.proposedStrategyTime(), 0);
        }
    }

    function test__pause() public {
        for (uint256 i; i < configLength; ++i) {
            _setUpTest(i);
            uint256 depositAmount = 1 ether;

            // Deposit funds for testing
            deal(address(asset), alice, depositAmount * 3);
            vm.startPrank(alice);
            asset.approve(address(vault), depositAmount * 3);
            vault.deposit(depositAmount * 2, alice);
            vm.stopPrank();

            vault.pause();

            assertTrue(vault.paused());

            vm.prank(alice);
            vm.expectRevert(); // maxDeposit()
            vault.deposit(depositAmount, alice);

            vm.prank(alice);
            vm.expectRevert(); // maxDeposit()
            vault.mint(depositAmount, alice);

            vm.prank(alice);
            vault.withdraw(depositAmount, alice, alice);

            vm.prank(alice);
            vault.redeem(depositAmount, alice, alice);
        }
    }

    function test__unpause() public {
        for (uint256 i; i < configLength; ++i) {
            _setUpTest(i);
            uint256 depositAmount = 1 ether;

            // Deposit funds for testing
            deal(address(asset), alice, depositAmount * 2);
            vm.prank(alice);
            asset.approve(address(vault), depositAmount * 2);

            vault.pause();

            vault.unpause();

            assertFalse(vault.paused());

            vm.prank(alice);
            vault.deposit(depositAmount, alice);

            vm.prank(alice);
            vault.mint(depositAmount, alice);

            vm.prank(alice);
            vault.withdraw(depositAmount, alice, alice);

            uint256 redeemAmount = vault.maxRedeem(alice);
            vm.prank(alice);
            vault.redeem(redeemAmount, alice, alice);
        }
    }
}
