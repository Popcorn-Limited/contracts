// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../utils/mocks/MockERC20.sol";
import {MockERC4626} from "../utils/mocks/MockERC4626.sol";
import {MultiStrategyVault, Allocation} from "../../src/vaults/MultiStrategyVault.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

contract MultiStrategyVaultTest is Test {
    using FixedPointMathLib for uint256;

    bytes32 constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    MockERC20 asset;
    IERC4626[] strategies;
    uint256[] withdrawalQueue;
    MultiStrategyVault vault;

    address strategyImplementation;
    address implementation;

    uint256 constant ONE = 1e18;

    address alice = address(0xABCD);
    address bob = address(0xDCBA);

    event NewStrategiesProposed();
    event ChangedStrategies();
    event Paused(address account);
    event Unpaused(address account);
    event DepositLimitSet(uint256 depositLimit);

    function setUp() public {
        vm.label(alice, "alice");
        vm.label(bob, "bob");

        asset = new MockERC20("Mock Token", "TKN", 18);

        strategyImplementation = address(new MockERC4626());
        implementation = address(new MultiStrategyVault());

        address vaultAddress = Clones.clone(implementation);
        vault = MultiStrategyVault(vaultAddress);
        vm.label(vaultAddress, "vault");

        strategies.push(_createStrategy(IERC20(address(asset))));
        strategies.push(_createStrategy(IERC20(address(asset))));

        withdrawalQueue.push(1);
        withdrawalQueue.push(0);

        vault.initialize(
            IERC20(address(asset)),
            strategies,
            uint256(0),
            withdrawalQueue,
            type(uint256).max,
            address(this)
        );
    }

    /*//////////////////////////////////////////////////////////////
                              HELPER
    //////////////////////////////////////////////////////////////*/

    function _createStrategy(IERC20 _asset) internal returns (IERC4626) {
        address strategyAddress = Clones.clone(strategyImplementation);
        MockERC4626(strategyAddress).initialize(
            _asset,
            "Mock Token Vault",
            "vwTKN"
        );
        return IERC4626(strategyAddress);
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__metadata() public {
        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);

        newVault.initialize(
            IERC20(address(asset)),
            strategies,
            uint256(0),
            withdrawalQueue,
            type(uint256).max,
            bob
        );

        assertEq(newVault.name(), "VaultCraft Mock Token Vault");
        assertEq(newVault.symbol(), "vc-TKN");
        assertEq(newVault.decimals(), 18);

        assertEq(address(newVault.asset()), address(asset));
        assertEq(address(newVault.strategies(0)), address(strategies[0]));
        assertEq(address(newVault.strategies(1)), address(strategies[1]));
        assertEq(newVault.owner(), bob);

        assertEq(newVault.quitPeriod(), 3 days);
        assertEq(
            asset.allowance(address(newVault), address(strategies[0])),
            type(uint256).max
        );
        assertEq(
            asset.allowance(address(newVault), address(strategies[1])),
            type(uint256).max
        );
    }

    function testFail__initialize_asset_is_zero() public {
        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);

        newVault.initialize(
            IERC20(address(0)),
            strategies,
            uint256(0),
            withdrawalQueue,
            type(uint256).max,
            address(this)
        );
    }

    function testFail__initialize_strategy_asset_is_not_matching() public {
        MockERC20 newAsset = new MockERC20("New Mock Token", "NTKN", 18);

        IERC4626[] memory newStrategies = new IERC4626[](1);
        newStrategies[0] = _createStrategy(IERC20(address(newAsset)));

        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);

        newVault.initialize(
            IERC20(address(asset)),
            newStrategies,
            uint256(0),
            withdrawalQueue,
            type(uint256).max,
            address(this)
        );
    }

    function testFail__initialize_strategy_addressZero() public {
        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);

        newVault.initialize(
            IERC20(address(asset)),
            new IERC4626[](1),
            uint256(0),
            withdrawalQueue,
            type(uint256).max,
            address(this)
        );
    }

    function testFail__initialize_depositIndex_out_of_bound() public {
        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);
        newVault.initialize(
            IERC20(address(asset)),
            strategies,
            uint256(3),
            withdrawalQueue,
            type(uint256).max,
            bob
        );
    }

    function testFail__initialize_withdrawalQueue_too_long() public {
        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);

        uint256[] memory newWithdrawalQueue = new uint256[](3);

        newVault.initialize(
            IERC20(address(asset)),
            strategies,
            uint256(0),
            newWithdrawalQueue,
            type(uint256).max,
            bob
        );
    }

    function testFail__initialize_withdrawalQueue_too_short() public {
        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);

        uint256[] memory newWithdrawalQueue = new uint256[](1);

        newVault.initialize(
            IERC20(address(asset)),
            strategies,
            uint256(0),
            newWithdrawalQueue,
            type(uint256).max,
            bob
        );
    }

    function testFail__initialize_withdrawalQueue_index_out_of_bounds() public {
        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);

        uint256[] memory newWithdrawalQueue = new uint256[](2);
        newWithdrawalQueue[0] = 0;
        newWithdrawalQueue[1] = uint256(2);

        newVault.initialize(
            IERC20(address(asset)),
            strategies,
            uint256(0),
            newWithdrawalQueue,
            type(uint256).max,
            bob
        );
    }

    function testFail__initialize_strategies_duplicates() public {
        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);

        IERC4626[] memory newStrategies = new IERC4626[](2);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;
        newStrategies[1] = newStrategy;

        newVault.initialize(
            IERC20(address(asset)),
            newStrategies,
            uint256(0),
            withdrawalQueue,
            type(uint256).max,
            bob
        );
    }

    function testFail__initialize_withdrawalQueue_duplicates() public {
        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);

        uint256[] memory newWithdrawalQueue = new uint256[](2);
        newWithdrawalQueue[0] = 0;
        newWithdrawalQueue[1] = 0;

        newVault.initialize(
            IERC20(address(asset)),
            strategies,
            uint256(0),
            newWithdrawalQueue,
            type(uint256).max,
            bob
        );
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT / WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function test__deposit_withdraw(uint128 amount) public {
        if (amount < 1) amount = 1;

        uint256 aliceassetAmount = amount;

        asset.mint(alice, aliceassetAmount);

        vm.prank(alice);
        asset.approve(address(vault), aliceassetAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceassetAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceShareAmount = vault.deposit(aliceassetAmount, alice);

        assertEq(
            MockERC4626(address(strategies[0])).afterDepositHookCalledCounter(),
            1
        );
        assertEq(
            MockERC4626(address(strategies[1])).afterDepositHookCalledCounter(),
            0
        );

        assertEq(aliceassetAmount, aliceShareAmount);
        assertEq(vault.previewWithdraw(aliceassetAmount), aliceShareAmount);
        assertEq(vault.previewDeposit(aliceassetAmount), aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), aliceassetAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        assertEq(
            vault.convertToAssets(vault.balanceOf(alice)),
            aliceassetAmount
        );
        assertEq(asset.balanceOf(alice), alicePreDepositBal - aliceassetAmount);

        vm.prank(alice);
        vault.withdraw(aliceassetAmount, alice, alice);

        assertEq(
            MockERC4626(address(strategies[0]))
                .beforeWithdrawHookCalledCounter(),
            1
        );
        assertEq(
            MockERC4626(address(strategies[1]))
                .beforeWithdrawHookCalledCounter(),
            0
        );

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(asset.balanceOf(alice), alicePreDepositBal);
    }

    function testFail__deposit_zero() public {
        vault.deposit(0, address(this));
    }

    function testFail__withdraw_zero() public {
        vault.withdraw(0, address(this), address(this));
    }

    function testFail__deposit_with_no_approval() public {
        vault.deposit(1e18, address(this));
    }

    function testFail__deposit_with_not_enough_approval() public {
        asset.mint(address(this), 1e18);
        asset.approve(address(vault), 0.5e18);
        assertEq(asset.allowance(address(this), address(vault)), 0.5e18);

        vault.deposit(1e18, address(this));
    }

    function testFail__withdraw_with_not_enough_assets() public {
        asset.mint(address(this), 0.5e18);
        asset.approve(address(vault), 0.5e18);

        vault.deposit(0.5e18, address(this));

        vault.withdraw(1e18, address(this), address(this));
    }

    function testFail__withdraw_with_no_assets() public {
        vault.withdraw(1e18, address(this), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          MINT / REDEEM
    //////////////////////////////////////////////////////////////*/

    function test__mint_redeem(uint128 amount) public {
        if (amount < 1) amount = 1;

        uint256 aliceShareAmount = amount;
        asset.mint(alice, aliceShareAmount);

        vm.prank(alice);
        asset.approve(address(vault), aliceShareAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceShareAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceAssetAmount = vault.mint(aliceShareAmount, alice);

        assertEq(
            MockERC4626(address(strategies[0])).afterDepositHookCalledCounter(),
            1
        );
        assertEq(
            MockERC4626(address(strategies[1])).afterDepositHookCalledCounter(),
            0
        );

        // Expect exchange rate to be 1:1 on initial mint.
        assertApproxEqAbs(
            aliceShareAmount,
            aliceAssetAmount,
            1,
            "share = assets"
        );
        assertApproxEqAbs(
            vault.previewWithdraw(aliceAssetAmount),
            aliceShareAmount,
            1,
            "pw"
        );
        assertApproxEqAbs(
            vault.previewDeposit(aliceAssetAmount),
            aliceShareAmount,
            1,
            "pd"
        );
        assertEq(vault.totalSupply(), aliceShareAmount, "ts");
        assertEq(vault.totalAssets(), aliceAssetAmount, "ta");
        assertEq(vault.balanceOf(alice), aliceShareAmount, "bal");
        assertApproxEqAbs(
            vault.convertToAssets(vault.balanceOf(alice)),
            aliceAssetAmount,
            1,
            "convert"
        );
        assertEq(
            asset.balanceOf(alice),
            alicePreDepositBal - aliceAssetAmount,
            "a bal"
        );

        vm.prank(alice);
        vault.redeem(aliceShareAmount, alice, alice);

        assertEq(
            MockERC4626(address(strategies[0]))
                .beforeWithdrawHookCalledCounter(),
            1
        );
        assertEq(
            MockERC4626(address(strategies[1]))
                .beforeWithdrawHookCalledCounter(),
            0
        );

        assertApproxEqAbs(vault.totalAssets(), 0, 1);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertApproxEqAbs(asset.balanceOf(alice), alicePreDepositBal, 1);
    }

    function testFail__mint_zero() public {
        vault.mint(0, address(this));
    }

    function testFail__redeem_zero() public {
        vault.redeem(0, address(this), address(this));
    }

    function testFail__mint_with_no_approval() public {
        vault.mint(1e18, address(this));
    }

    function testFail__mint_with_not_enough_approval() public {
        asset.mint(address(this), 1e18);
        asset.approve(address(vault), 1e6);
        assertEq(asset.allowance(address(this), address(vault)), 1e6);

        vault.mint(1e18, address(this));
    }

    function testFail__redeem_with_not_enough_shares() public {
        asset.mint(address(this), 0.5e18);
        asset.approve(address(vault), 0.5e18);

        vault.deposit(0.5e18, address(this));

        vault.redeem(1e18, address(this), address(this));
    }

    function testFail__redeem_with_no_shares() public {
        vault.redeem(1e18, address(this), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                DEPOSIT / MINT / WITHDRAW / REDEEM
    //////////////////////////////////////////////////////////////*/

    function test__interactions_for_someone_else() public {
        // init 2 users with a 1e18 balance
        asset.mint(alice, 1e18);
        asset.mint(bob, 1e18);

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
        assertEq(asset.balanceOf(bob), 1e18);

        // bob withdraw 1e18 for alice
        vm.prank(bob);
        vault.withdraw(1e18, alice, bob);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(asset.balanceOf(alice), 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                          NO STRATEGIES
    //////////////////////////////////////////////////////////////*/

    function _createVaultWithoutStrategies()
        internal
        returns (MultiStrategyVault)
    {
        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);

        IERC4626[] memory newStrategies;
        uint256[] memory newWithdrawalQueue;

        newVault.initialize(
            IERC20(address(asset)),
            newStrategies,
            type(uint256).max,
            newWithdrawalQueue,
            type(uint256).max,
            bob
        );
        return newVault;
    }

    function test__init_no_strategies() public {
        MultiStrategyVault newVault = _createVaultWithoutStrategies();

        assertEq(newVault.getStrategies().length, 0);
        assertEq(newVault.getWithdrawalQueue().length, 0);
        assertEq(newVault.depositIndex(), type(uint256).max);
    }

    function testFail__init_no_strategies_defaultIndex_wrong() public {
        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);

        IERC4626[] memory newStrategies;
        uint256[] memory newWithdrawalQueue;

        newVault.initialize(
            IERC20(address(asset)),
            newStrategies,
            0,
            newWithdrawalQueue,
            type(uint256).max,
            address(this)
        );
    }

    function testFail__init_no_strategies_withdrawalQueue_wrong() public {
        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);

        IERC4626[] memory newStrategies;
        uint256[] memory newWithdrawalQueue = new uint256[](1);

        newVault.initialize(
            IERC20(address(asset)),
            newStrategies,
            0,
            newWithdrawalQueue,
            type(uint256).max,
            address(this)
        );
    }

    function test__deposit_withdrawal_no_strategies(uint128 amount) public {
        MultiStrategyVault newVault = _createVaultWithoutStrategies();
        if (amount < 1) amount = 1;

        uint256 aliceassetAmount = amount;

        asset.mint(alice, aliceassetAmount);

        vm.prank(alice);
        asset.approve(address(newVault), aliceassetAmount);
        assertEq(asset.allowance(alice, address(newVault)), aliceassetAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceShareAmount = newVault.deposit(aliceassetAmount, alice);

        assertEq(aliceassetAmount, aliceShareAmount);
        assertEq(newVault.previewWithdraw(aliceassetAmount), aliceShareAmount);
        assertEq(newVault.previewDeposit(aliceassetAmount), aliceShareAmount);
        assertEq(newVault.totalSupply(), aliceShareAmount);
        assertEq(newVault.totalAssets(), aliceassetAmount);
        assertEq(newVault.balanceOf(alice), aliceShareAmount);
        assertEq(
            newVault.convertToAssets(newVault.balanceOf(alice)),
            aliceassetAmount
        );
        assertEq(asset.balanceOf(alice), alicePreDepositBal - aliceassetAmount);

        vm.prank(alice);
        newVault.withdraw(aliceassetAmount, alice, alice);

        assertEq(newVault.totalAssets(), 0);
        assertEq(newVault.balanceOf(alice), 0);
        assertEq(newVault.convertToAssets(newVault.balanceOf(alice)), 0);
        assertEq(asset.balanceOf(alice), alicePreDepositBal);
    }

    function test__mint_redeem_no_strategies(uint128 amount) public {
        MultiStrategyVault newVault = _createVaultWithoutStrategies();

        if (amount < 1) amount = 1;

        uint256 aliceShareAmount = amount;
        asset.mint(alice, aliceShareAmount);

        vm.prank(alice);
        asset.approve(address(newVault), aliceShareAmount);
        assertEq(asset.allowance(alice, address(newVault)), aliceShareAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceAssetAmount = newVault.mint(aliceShareAmount, alice);

        // Expect exchange rate to be 1:1 on initial mint.
        assertApproxEqAbs(
            aliceShareAmount,
            aliceAssetAmount,
            1,
            "share = assets"
        );
        assertApproxEqAbs(
            newVault.previewWithdraw(aliceAssetAmount),
            aliceShareAmount,
            1,
            "pw"
        );
        assertApproxEqAbs(
            newVault.previewDeposit(aliceAssetAmount),
            aliceShareAmount,
            1,
            "pd"
        );
        assertEq(newVault.totalSupply(), aliceShareAmount, "ts");
        assertEq(newVault.totalAssets(), aliceAssetAmount, "ta");
        assertEq(newVault.balanceOf(alice), aliceShareAmount, "bal");
        assertApproxEqAbs(
            newVault.convertToAssets(newVault.balanceOf(alice)),
            aliceAssetAmount,
            1,
            "convert"
        );
        assertEq(
            asset.balanceOf(alice),
            alicePreDepositBal - aliceAssetAmount,
            "a bal"
        );

        vm.prank(alice);
        newVault.redeem(aliceShareAmount, alice, alice);

        assertApproxEqAbs(newVault.totalAssets(), 0, 1);
        assertEq(newVault.balanceOf(alice), 0);
        assertEq(newVault.convertToAssets(newVault.balanceOf(alice)), 0);
        assertApproxEqAbs(asset.balanceOf(alice), alicePreDepositBal, 1);
    }

    function test__setStrategies_no_strategies() public {
        MultiStrategyVault newVault = _createVaultWithoutStrategies();

        vm.prank(bob);
        newVault.proposeStrategies(strategies, withdrawalQueue, uint256(0));

        vm.warp(block.timestamp + 3 days + 1);

        newVault.changeStrategies();
        assertEq(newVault.getStrategies().length, 2);
        assertEq(newVault.getProposedStrategies().length, 0);
    }

    function testFail__setWithdrawalQueue() public {
        MultiStrategyVault newVault = _createVaultWithoutStrategies();

        uint256[] memory indexes = new uint256[](1);

        vm.prank(bob);
        newVault.setWithdrawalQueue(indexes);
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE STRATEGY
    //////////////////////////////////////////////////////////////*/

    // Propose Strategy
    function test__proposeStrategies() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;

        uint256[] memory newWithdrawalQueue = new uint256[](1);
        newWithdrawalQueue[0] = uint256(0);

        vm.expectEmit(false, false, false, true, address(vault));
        emit NewStrategiesProposed();

        uint256 callTime = block.timestamp;
        vault.proposeStrategies(newStrategies, newWithdrawalQueue, uint256(0));

        IERC4626[] memory proposedStrategies = vault.getProposedStrategies();
        uint256[] memory proposedWithdrawalQueue = vault
            .getProposedWithdrawalQueue();

        assertEq(proposedStrategies.length, 1);
        assertEq(address(proposedStrategies[0]), address(newStrategy));
        assertEq(proposedWithdrawalQueue.length, 1);
        assertEq(proposedWithdrawalQueue[0], uint256(0));
        assertEq(vault.proposedDepositIndex(), uint256(0));
        assertEq(vault.proposedStrategyTime(), callTime);
    }

    function test__proposeStrategies_depositIndex_max() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;

        uint256[] memory newWithdrawalQueue = new uint256[](1);
        newWithdrawalQueue[0] = uint256(0);

        vm.expectEmit(false, false, false, true, address(vault));
        emit NewStrategiesProposed();

        uint256 callTime = block.timestamp;
        vault.proposeStrategies(
            newStrategies,
            newWithdrawalQueue,
            type(uint256).max
        );

        IERC4626[] memory proposedStrategies = vault.getProposedStrategies();
        uint256[] memory proposedWithdrawalQueue = vault
            .getProposedWithdrawalQueue();

        assertEq(proposedStrategies.length, 1);
        assertEq(address(proposedStrategies[0]), address(newStrategy));
        assertEq(proposedWithdrawalQueue.length, 1);
        assertEq(proposedWithdrawalQueue[0], uint256(0));
        assertEq(vault.proposedDepositIndex(), type(uint256).max);
        assertEq(vault.proposedStrategyTime(), callTime);
    }

    function test__proposeStrategies_no_strategies() public {
        IERC4626[] memory newStrategies;

        uint256[] memory newWithdrawalQueue;

        vm.expectEmit(false, false, false, true, address(vault));
        emit NewStrategiesProposed();

        uint256 callTime = block.timestamp;
        vault.proposeStrategies(
            newStrategies,
            newWithdrawalQueue,
            type(uint256).max
        );

        IERC4626[] memory proposedStrategies = vault.getProposedStrategies();
        uint256[] memory proposedWithdrawalQueue = vault
            .getProposedWithdrawalQueue();

        assertEq(proposedStrategies.length, 0);
        assertEq(proposedWithdrawalQueue.length, 0);
        assertEq(vault.proposedDepositIndex(), type(uint256).max);
        assertEq(vault.proposedStrategyTime(), callTime);
    }

    function testFail__proposeStrategies_nonOwner() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;

        uint256[] memory newWithdrawalQueue = new uint256[](1);
        newWithdrawalQueue[0] = uint256(0);

        vm.prank(alice);
        vault.proposeStrategies(newStrategies, newWithdrawalQueue, uint256(0));
    }

    function testFail__proposeStrategies_asset_mismatch() public {
        MockERC20 newAsset = new MockERC20("New Mock Token", "NTKN", 18);

        IERC4626[] memory newStrategies = new IERC4626[](1);
        newStrategies[0] = _createStrategy(IERC20(address(newAsset)));

        uint256[] memory newWithdrawalQueue = new uint256[](1);

        vault.proposeStrategies(newStrategies, newWithdrawalQueue, uint256(0));
    }

    function testFail__proposeStrategies_depositIndex_out_of_bounds() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        newStrategies[0] = _createStrategy(IERC20(address(asset)));

        uint256[] memory newWithdrawalQueue = new uint256[](1);

        vm.prank(alice);
        vault.proposeStrategies(newStrategies, newWithdrawalQueue, uint256(2));
    }

    function testFail__proposeStrategies_withdrawalQueue_too_long() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        newStrategies[0] = _createStrategy(IERC20(address(asset)));

        uint256[] memory newWithdrawalQueue = new uint256[](2);

        vm.prank(alice);
        vault.proposeStrategies(newStrategies, newWithdrawalQueue, uint256(0));
    }

    function testFail__proposeStrategies_withdrawalQueue_too_short() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;

        uint256[] memory newWithdrawalQueue;

        vm.prank(alice);
        vault.proposeStrategies(newStrategies, newWithdrawalQueue, uint256(0));
    }

    function testFail__proposeStrategies_withdrawalQueue_out_of_bounds()
        public
    {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        newStrategies[0] = _createStrategy(IERC20(address(asset)));

        uint256[] memory newWithdrawalQueue = new uint256[](1);
        newWithdrawalQueue[0] = uint256(1);

        vm.prank(alice);
        vault.proposeStrategies(newStrategies, newWithdrawalQueue, uint256(0));
    }

    function testFail__proposeStrategies_duplicates() public {
        IERC4626[] memory newStrategies = new IERC4626[](2);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;
        newStrategies[1] = newStrategy;

        uint256[] memory newWithdrawalQueue = new uint256[](2);
        newWithdrawalQueue[0] = uint256(0);
        newWithdrawalQueue[1] = uint256(1);

        vm.prank(alice);
        vault.proposeStrategies(newStrategies, newWithdrawalQueue, uint256(0));
    }

    function testFail__proposeStrategies__withdrawalQueue_duplicates() public {
        IERC4626[] memory newStrategies = new IERC4626[](2);
        newStrategies[0] = _createStrategy(IERC20(address(asset)));
        newStrategies[1] = _createStrategy(IERC20(address(asset)));

        uint256[] memory newWithdrawalQueue = new uint256[](2);
        newWithdrawalQueue[0] = uint256(0);
        newWithdrawalQueue[1] = uint256(0);

        vm.prank(alice);
        vault.proposeStrategies(newStrategies, newWithdrawalQueue, uint256(0));
    }

    function testFail__proposeStrategies_no_strategies_depositIndex_out_of_bounds()
        public
    {
        IERC4626[] memory newStrategies;

        uint256[] memory newWithdrawalQueue;

        vm.expectEmit(false, false, false, true, address(vault));
        emit NewStrategiesProposed();

        vault.proposeStrategies(newStrategies, newWithdrawalQueue, 0);
    }

    // Change Strategy
    function test__changeStrategies() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;

        uint256[] memory newWithdrawalQueue = new uint256[](1);
        newWithdrawalQueue[0] = uint256(0);

        uint256 depositAmount = 1 ether;

        // Deposit funds for testing
        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Preparation to change the strategies
        vault.proposeStrategies(newStrategies, newWithdrawalQueue, uint256(0));

        vm.warp(block.timestamp + 3 days);

        vault.changeStrategies();

        assertEq(asset.allowance(address(vault), address(strategies[0])), 0);
        assertEq(asset.allowance(address(vault), address(strategies[1])), 0);

        // Annoyingly Math fails us here and leaves 1 asset in the adapter
        assertEq(asset.balanceOf(address(strategies[0])), 0);
        assertEq(asset.balanceOf(address(strategies[1])), 0);

        assertEq(strategies[0].balanceOf(address(vault)), 0);

        assertEq(asset.balanceOf(address(newStrategy)), 0);
        assertEq(asset.balanceOf(address(vault)), depositAmount);
        assertEq(
            asset.allowance(address(vault), address(newStrategy)),
            type(uint256).max
        );

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

    function test__changeStrategies_to_no_strategies() public {
        IERC4626[] memory newStrategies;

        uint256[] memory newWithdrawalQueue;

        uint256 depositAmount = 1 ether;

        // Deposit funds for testing
        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Preparation to change the strategies
        vault.proposeStrategies(
            newStrategies,
            newWithdrawalQueue,
            type(uint256).max
        );

        vm.warp(block.timestamp + 3 days);

        vault.changeStrategies();

        assertEq(asset.allowance(address(vault), address(strategies[0])), 0);
        assertEq(asset.allowance(address(vault), address(strategies[1])), 0);

        // Annoyingly Math fails us here and leaves 1 asset in the adapter
        assertEq(asset.balanceOf(address(strategies[0])), 0);
        assertEq(asset.balanceOf(address(strategies[1])), 0);

        assertEq(strategies[0].balanceOf(address(vault)), 0);

        assertEq(asset.balanceOf(address(vault)), depositAmount);

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

    function testFail__changeStrategies_respect_rageQuit() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;

        uint256[] memory newWithdrawalQueue = new uint256[](1);

        vault.proposeStrategies(newStrategies, newWithdrawalQueue, uint256(0));

        // Didnt respect 3 days before propsal and change
        vault.changeStrategies();
    }

    function testFail__changeStrategies_after_init() public {
        vault.changeStrategies();
    }

    function testFail__changeStrategies_instantly_again() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;

        uint256[] memory newWithdrawalQueue = new uint256[](1);

        uint256 depositAmount = 1 ether;

        // Deposit funds for testing
        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Preparation to change the adapter
        vault.proposeStrategies(newStrategies, newWithdrawalQueue, uint256(0));

        vm.warp(block.timestamp + 3 days);

        vm.expectEmit(false, false, false, true, address(vault));
        emit ChangedStrategies();

        vault.changeStrategies();
        vault.changeStrategies();
    }

    function testFail_changeWithdrawalQueue_invalidLength() public {
        uint256[] memory newWithdrawalQueue = new uint256[](1);
        newWithdrawalQueue[0] = 0;

        vault.setWithdrawalQueue(newWithdrawalQueue);
    }

    function testFail_changeWithdrawalQueue_invalidIndex() public {
        uint256[] memory newWithdrawalQueue = new uint256[](2);
        newWithdrawalQueue[0] = 5;
        newWithdrawalQueue[1] = 0;

        vault.setWithdrawalQueue(newWithdrawalQueue);
    }

    /*//////////////////////////////////////////////////////////////
                          PULL AND PUSH FUNDS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_fundsIdle() public {
        // set default index to be type max
        vault.setDepositIndex(type(uint256).max);

        uint256 amount = 1e18;
        _depositIntoVault(bob, amount);

        assertEq(asset.balanceOf(address(strategies[0])), 0);
        assertEq(asset.balanceOf(address(strategies[1])), 0);
        assertEq(asset.balanceOf(address(vault)), amount);
    }

    function test_withdrawIdleFunds() public {
        // set default index to be type max
        vault.setDepositIndex(type(uint256).max);

        uint256 amount = 1e18;
        _depositIntoVault(bob, amount);

        assertEq(asset.balanceOf(address(strategies[0])), 0);
        assertEq(asset.balanceOf(address(strategies[1])), 0);
        assertEq(asset.balanceOf(address(vault)), amount);

        uint256 balBobBefore = asset.balanceOf(bob);

        vm.prank(bob);
        vault.withdraw(amount);

        assertEq(asset.balanceOf(address(strategies[0])), 0);
        assertEq(asset.balanceOf(address(strategies[1])), 0);
        assertEq(asset.balanceOf(address(vault)), 0);

        assertEq(asset.balanceOf(bob), balBobBefore + amount);
    }

    function test_withdraw_queueOrder() public {
        _depositIntoVault(bob, 10e18);

        assertEq(asset.balanceOf(address(strategies[0])), 10e18);
        assertEq(asset.balanceOf(address(strategies[1])), 0);

        Allocation[] memory allocations = new Allocation[](2);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vault.pullFunds(allocations);

        allocations[0] = Allocation({index: 0, amount: 1e18});
        allocations[1] = Allocation({index: 1, amount: 9e18});

        vault.pushFunds(allocations);

        assertEq(asset.balanceOf(address(strategies[1])), 9e18);
        assertEq(asset.balanceOf(address(strategies[0])), 1e18);

        uint256[] memory newWithdrawalQueue = new uint256[](2);
        newWithdrawalQueue[0] = 1;
        newWithdrawalQueue[1] = 0;

        vault.setWithdrawalQueue(newWithdrawalQueue);

        vm.prank(bob);
        vault.withdraw(95e17);

        assertEq(asset.balanceOf(address(strategies[1])), 0);
        assertEq(asset.balanceOf(address(strategies[0])), 5e17);
    }

    function testFail_setDefaultIndex_invalidIndex() public {
        vault.setDepositIndex(5);
    }

    function _depositIntoVault(address user, uint256 amount) internal {
        asset.mint(user, amount);

        vm.startPrank(user);
        asset.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    function test__pullFunds() public {
        _depositIntoVault(bob, 10e18);

        assertEq(asset.balanceOf(address(strategies[0])), 10e18);
        assertEq(asset.balanceOf(address(strategies[1])), 0);

        Allocation[] memory allocations = new Allocation[](2);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vault.pullFunds(allocations);

        assertEq(asset.balanceOf(address(strategies[0])), 0);
        assertEq(asset.balanceOf(address(strategies[1])), 0);
        assertEq(asset.balanceOf(address(vault)), 10e18);
    }

    function testFail__pullFunds_noOwner() public {
        _depositIntoVault(bob, 10e18);
        Allocation[] memory allocations = new Allocation[](1);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vm.prank(alice);
        vault.pullFunds(allocations);
    }

    function testFail__pullFunds_indexOutOfBounds() public {
        _depositIntoVault(bob, 10e18);
        Allocation[] memory allocations = new Allocation[](1);
        allocations[0] = Allocation({index: 2, amount: 10e18});

        vault.pullFunds(allocations);
    }

    function testFail__pullFunds_notEnoughFunds() public {
        _depositIntoVault(bob, 10e18);
        Allocation[] memory allocations = new Allocation[](1);
        allocations[0] = Allocation({index: 0, amount: 11e18});

        vault.pullFunds(allocations);
    }

    function test__pushFunds() public {
        _depositIntoVault(bob, 10e18);

        assertEq(asset.balanceOf(address(strategies[0])), 10e18);
        assertEq(asset.balanceOf(address(strategies[1])), 0);

        Allocation[] memory allocations = new Allocation[](2);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vault.pullFunds(allocations);

        allocations[0] = Allocation({index: 0, amount: 1e18});
        allocations[1] = Allocation({index: 1, amount: 9e18});

        vault.pushFunds(allocations);

        assertEq(asset.balanceOf(address(strategies[0])), 1e18);
        assertEq(asset.balanceOf(address(strategies[1])), 9e18);
    }

    function testFail__pushFunds_noOwner() public {
        _depositIntoVault(bob, 10e18);

        Allocation[] memory allocations = new Allocation[](2);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vault.pullFunds(allocations);

        allocations[0] = Allocation({index: 0, amount: 1e18});
        allocations[1] = Allocation({index: 1, amount: 9e18});

        vm.prank(alice);
        vault.pushFunds(allocations);
    }

    function testFail__pushFunds_indexOutOfBounds() public {
        _depositIntoVault(bob, 10e18);

        Allocation[] memory allocations = new Allocation[](2);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vault.pullFunds(allocations);

        allocations[0] = Allocation({index: 0, amount: 1e18});
        allocations[1] = Allocation({index: 2, amount: 9e18});

        vault.pushFunds(allocations);
    }

    function testFail__pushFunds_notEnoughFunds() public {
        _depositIntoVault(bob, 10e18);

        Allocation[] memory allocations = new Allocation[](2);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vault.pullFunds(allocations);

        allocations[0] = Allocation({index: 0, amount: 1e18});
        allocations[1] = Allocation({index: 1, amount: 10e18});

        vault.pushFunds(allocations);
    }

    /*//////////////////////////////////////////////////////////////
                        PERFORMANCE FEE
    //////////////////////////////////////////////////////////////*/

    event PerformanceFeeChanged(uint256 oldFee, uint256 newFee);

    function test__setPerformanceFee() public {
        vm.expectEmit(false, false, false, true, address(vault));
        emit PerformanceFeeChanged(0, 1e16);
        vault.setPerformanceFee(1e16);

        assertEq(vault.performanceFee(), 1e16);
    }

    function testFail__setPerformanceFee_nonOwner() public {
        vm.prank(alice);
        vault.setPerformanceFee(1e16);
    }

    function testFail__setPerformanceFee_invalid_fee() public {
        vault.setPerformanceFee(3e17);
    }

    /*//////////////////////////////////////////////////////////////
                          SET DEPOSIT LIMIT
    //////////////////////////////////////////////////////////////*/

    function test__setDepositLimit() public {
        uint256 newDepositLimit = 100;
        vm.expectEmit(false, false, false, true, address(vault));
        emit DepositLimitSet(newDepositLimit);

        vault.setDepositLimit(newDepositLimit);

        assertEq(vault.depositLimit(), newDepositLimit);

        asset.mint(address(this), 101);
        asset.approve(address(vault), 101);

        vm.expectRevert(); // maxDeposit
        vault.deposit(101, address(this));

        vm.expectRevert(); // maxDeposit
        vault.mint(101, address(this));
    }

    function testFail__setDepositLimit_NonOwner() public {
        vm.prank(alice);
        vault.setDepositLimit(uint256(100));
    }

    /*//////////////////////////////////////////////////////////////
                                PAUSE
    //////////////////////////////////////////////////////////////*/

    // Pause
    function test__pause() public {
        uint256 depositAmount = 1 ether;

        // Deposit funds for testing
        asset.mint(alice, depositAmount * 3);
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount * 3);
        vault.deposit(depositAmount * 2, alice);
        vm.stopPrank();

        vm.expectEmit(false, false, false, true, address(vault));
        emit Paused(address(this));

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

    function testFail__pause_nonOwner() public {
        vm.prank(alice);
        vault.pause();
    }

    // Unpause
    function test__unpause() public {
        uint256 depositAmount = 1 ether;

        // Deposit funds for testing
        asset.mint(alice, depositAmount * 2);
        vm.prank(alice);
        asset.approve(address(vault), depositAmount * 2);

        vault.pause();

        vm.expectEmit(false, false, false, true, address(vault));
        emit Unpaused(address(this));

        vault.unpause();

        assertFalse(vault.paused());

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.prank(alice);
        vault.mint(depositAmount, alice);

        vm.prank(alice);
        vault.withdraw(depositAmount, alice, alice);

        vm.prank(alice);
        vault.redeem(depositAmount, alice, alice);
    }

    function testFail__unpause_nonOwner() public {
        vault.pause();

        vm.prank(alice);
        vault.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                              PERMIT
    //////////////////////////////////////////////////////////////*/

    function test_permit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    vault.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        vault.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);

        assertEq(vault.allowance(owner, address(0xCAFE)), 1e18);
        assertEq(vault.nonces(owner), 1);
    }
}