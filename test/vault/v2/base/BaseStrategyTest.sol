// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import "../../../../src/vault/v2/vaults/SingleStrategyVault.sol";
import {ITestConfigStorage, TestConfig} from "./interfaces/ITestConfigStorage.sol";
import {PropertyTest} from "../../adapter/abstract/PropertyTest.prop.sol";
import {IVault} from "../../../../src/vault/v2/base/interfaces/IVault.sol";
import {AdapterConfig, ProtocolConfig, IBaseAdapter} from "../../../../src/vault/v2/base/interfaces/IBaseAdapter.sol";
import {IERC20Upgradeable as IERC20, IERC20MetadataUpgradeable as IERC20Metadata} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

abstract contract BaseAdapterTest is Test {
    using Math for uint256;

    ITestConfigStorage public testConfigStorage;

    TestConfig public testConfig;

    IBaseAdapter public strategy;

    address public bob;
    address public alice;
    address public owner;

    function _setUpBaseTest(uint256 i) internal virtual {
        TestConfig memory testConfig_ = testConfigStorage.testConfigs(i);

        uint256 forkId = testConfig_.blockNumber > 0
            ? vm.createSelectFork(
                vm.rpcUrl(testConfig_.network),
                testConfig_.blockNumber
            )
            : vm.createSelectFork(vm.rpcUrl(testConfig_.network));
        vm.selectFork(forkId);

        testConfig = testConfig_;

        VmSafe.Wallet memory _bob = vm.createWallet("bob");
        bob = _bob.addr;
        vm.label(bob, "bob");

        VmSafe.Wallet memory _alice = vm.createWallet("alice");
        alice = _alice.addr;
        vm.label(alice, "alice");

        VmSafe.Wallet memory _owner = vm.createWallet("owner");
        owner = _owner.addr;
        vm.label(owner, "owner");

        strategy = IBaseAdapter(_setUpStrategy(i, owner));

        vm.prank(owner);
        strategy.addVault(bob);

        vm.prank(owner);
        strategy.addVault(alice);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPER
    //////////////////////////////////////////////////////////////*/

    /// @dev -- This MUST be overriden to setup a strategy
    function _setUpStrategy(
        uint256 i_,
        address owner_
    ) internal virtual returns (address) {}

    function _mintAsset(uint256 amount, address receiver) internal virtual {
        deal(address(testConfig.asset), receiver, amount);
    }

    function _mintAssetAndApproveForStrategy(
        uint256 amount,
        address receiver
    ) internal {
        _mintAsset(amount, receiver);
        vm.prank(receiver);
        testConfig.asset.approve(address(strategy), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            PROP TESTS
    //////////////////////////////////////////////////////////////*/

    function prop_deposit(
        address caller,
        uint256 assets,
        string memory testPreFix
    ) public virtual {
        _mintAssetAndApproveForStrategy(assets, caller);

        uint256 oldCallerAsset = IERC20(testConfig.asset).balanceOf(caller);
        uint256 oldAllowance = IERC20(testConfig.asset).allowance(
            caller,
            address(strategy)
        );
        uint256 oldTotalAssets = strategy.totalAssets();

        vm.prank(caller);
        strategy.deposit(assets);

        uint256 newCallerAsset = IERC20(testConfig.asset).balanceOf(caller);
        uint256 newAllowance = IERC20(testConfig.asset).allowance(
            caller,
            address(strategy)
        );
        uint256 newTotalAssets = strategy.totalAssets();

        assertApproxEqAbs(
            newCallerAsset,
            oldCallerAsset - assets,
            testConfig.depositDelta,
            string.concat("balance", testPreFix)
        ); // NOTE: this may fail if the caller is a contract in which the asset is stored
        if (oldAllowance != type(uint256).max)
            assertApproxEqAbs(
                newAllowance,
                oldAllowance - assets,
                testConfig.depositDelta,
                string.concat("allowance", testPreFix)
            );

        assertApproxEqAbs(
            newTotalAssets,
            oldTotalAssets + assets,
            testConfig.depositDelta,
            string.concat("totalAssets", testPreFix)
        );
    }

    function prop_withdraw(
        address caller,
        address receiver,
        uint256 assets,
        string memory testPreFix
    ) public virtual {
        uint256 oldReceiverAsset = IERC20(testConfig.asset).balanceOf(receiver);
        uint256 oldTotalAssets = strategy.totalAssets();

        vm.prank(caller);
        strategy.withdraw(assets, receiver);

        uint256 newReceiverAsset = IERC20(testConfig.asset).balanceOf(receiver);
        uint256 newTotalAssets = strategy.totalAssets();

        assertApproxEqAbs(
            newReceiverAsset,
            oldReceiverAsset + assets,
            testConfig.withdrawDelta,
            string.concat("balance", testPreFix)
        ); // NOTE: this may fail if the receiver is a contract in which the asset is stored
        assertApproxEqAbs(
            newTotalAssets,
            oldTotalAssets - assets,
            testConfig.withdrawDelta,
            string.concat("totalAssets", testPreFix)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /*
     * @dev This function checks that the invariants in the strategy initialization function are checked:
     *      Some of the invariants that could be checked:
     *      - check that all errors in the strategy init function revert.
     *      - specific protocol or strategy config are verified in the registry.
     *      - correct allowance amounts are approved
     */
    function test__initialization() public virtual {}

    /*//////////////////////////////////////////////////////////////
                          TOTAL ASSETS
    //////////////////////////////////////////////////////////////*/

    /// @dev - This MUST be overriden to test that totalAssets adds up the the expected values
    function test__totalAssets() public virtual {}

    /*//////////////////////////////////////////////////////////////
                          MAX VIEWS
    //////////////////////////////////////////////////////////////*/

    /// NOTE: These Are just prop tests currently. Override tests here if the adapter has unique max-functions which override AdapterBase.sol
    function test__maxDeposit() public virtual {
        assertEq(strategy.maxDeposit(), type(uint256).max);

        vm.prank(owner);
        strategy.pause();

        assertEq(strategy.maxDeposit(), 0);
    }

    /// NOTE: These Are just prop tests currently. Override tests here if the adapter has unique max-functions which override AdapterBase.sol
    function test__maxWithdraw() public virtual {
        assertEq(strategy.maxWithdraw(), 0);

        _mintAssetAndApproveForStrategy(
            testConfig.defaultAmount,
            address(this)
        );

        strategy.deposit(testConfig.defaultAmount);
        assertEq(strategy.maxWithdraw(), testConfig.defaultAmount);

        vm.prank(owner);
        strategy.pause();

        assertEq(strategy.maxWithdraw(), testConfig.defaultAmount);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/MINT/WITHDRAW/REDEEM
    //////////////////////////////////////////////////////////////*/

    function test__deposit(uint8 fuzzAmount) public virtual {
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) _setUpBaseTest(i);
            uint256 amount = bound(
                uint256(fuzzAmount),
                testConfig.minDeposit,
                testConfig.maxDeposit
            );

            prop_deposit(bob, amount, testConfig.testId);

            prop_deposit(alice, amount, testConfig.testId);
        }
    }

    function testFail__deposit_zero_assets() public virtual {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(0);
    }

    function testFail__deposit_nonVault() public virtual {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, owner);

        vm.prank(owner);
        strategy.deposit(testConfig.defaultAmount);
    }

    function testFail__deposit_paused() public virtual {
        vm.prank(owner);
        strategy.pause();

        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount);
    }

    // TODO - should we add a buffer here or make depositAmont = amount?
    function test__withdraw(uint8 fuzzAmount) public virtual {
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) _setUpBaseTest(i);
            uint256 amount = bound(
                uint256(fuzzAmount),
                testConfig.minWithdraw,
                testConfig.maxWithdraw
            );
            uint256 depositAmount = amount * 2;

            _mintAssetAndApproveForStrategy(depositAmount, bob);
            vm.prank(bob);
            strategy.deposit(depositAmount);

            prop_withdraw(bob, alice, amount, testConfig.testId);

            _mintAssetAndApproveForStrategy(depositAmount, alice);
            vm.prank(alice);
            strategy.deposit(depositAmount);

            prop_withdraw(alice, alice, amount, testConfig.testId);
        }
    }

    // TODO - should we add a buffer here or make depositAmont = amount?
    function test__withdraw_while_paused() public virtual {
        uint256 depositAmount = testConfig.defaultAmount * 2;
        _mintAssetAndApproveForStrategy(depositAmount, bob);

        vm.prank(bob);
        strategy.deposit(depositAmount);

        vm.prank(owner);
        strategy.pause();

        prop_withdraw(bob, alice, testConfig.defaultAmount, testConfig.testId);
    }

    // TODO - should we add a buffer here or make depositAmont = amount?
    function testFail__withdraw_nonVault() public virtual {
        uint256 depositAmount = testConfig.defaultAmount * 2;
        _mintAssetAndApproveForStrategy(depositAmount, bob);

        vm.prank(bob);
        strategy.deposit(depositAmount);

        vm.prank(owner);
        strategy.withdraw(testConfig.defaultAmount, owner);
    }

    /*//////////////////////////////////////////////////////////////
                            ADD_VAULT
    //////////////////////////////////////////////////////////////*/

    // TODO should we add the ability to simply set a vault? so add or remove?
    function test__addVault() public virtual {
        address newVault = address(0x3333);

        assertFalse(strategy.isVault(newVault));

        vm.prank(owner);
        strategy.addVault(newVault);

        assertTrue(strategy.isVault(newVault));
    }

    function testFail__addVault_nonOwner() public virtual {
        vm.prank(alice);
        strategy.addVault(alice);
    }

    /*//////////////////////////////////////////////////////////////
                            REWARD_TOKENS
    //////////////////////////////////////////////////////////////*/

    function test__setRewardsToken() public virtual {
        IERC20[] memory newRewardTokens = new IERC20[](2);
        newRewardTokens[0] = IERC20(address(0x1111));
        newRewardTokens[1] = IERC20(address(0x2222));

        vm.prank(owner);
        strategy.setRewardsToken(newRewardTokens);

        IERC20[] memory actualRewardTokens = strategy.rewardTokens();
        assertEq(actualRewardTokens.length, 2);
        assertEq(address(actualRewardTokens[0]), address(0x1111));
        assertEq(address(actualRewardTokens[1]), address(0x2222));
    }

    function testFail__setRewardsToken_nonOwner() public virtual {
        IERC20[] memory newRewardTokens = new IERC20[](2);

        vm.prank(alice);
        strategy.setRewardsToken(newRewardTokens);
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSING
    //////////////////////////////////////////////////////////////*/

    function test__pause() public virtual {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount);

        uint256 oldTotalAssets = strategy.totalAssets();

        vm.prank(owner);
        strategy.pause();

        // We simply withdraw into the strategy
        // TotalSupply and Assets dont change
        assertApproxEqAbs(
            oldTotalAssets,
            strategy.totalAssets(),
            testConfig.withdrawDelta,
            "totalAssets"
        );
        assertApproxEqAbs(
            testConfig.asset.balanceOf(address(strategy)),
            oldTotalAssets,
            testConfig.withdrawDelta,
            "asset balance"
        );
    }

    function testFail__pause_nonOwner() public virtual {
        vm.prank(alice);
        strategy.pause();
    }

    function test__unpause() public virtual {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount * 3, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount * 3);

        uint256 oldTotalAssets = strategy.totalAssets();

        vm.prank(owner);
        strategy.pause();

        vm.prank(owner);
        strategy.unpause();

        uint256 delta = testConfig.withdrawDelta > testConfig.depositDelta
            ? testConfig.withdrawDelta
            : testConfig.depositDelta;

        // We simply deposit back into the external protocol
        // TotalAssets shouldnt change significantly besides some slippage or rounding errors
        assertApproxEqAbs(
            oldTotalAssets,
            strategy.totalAssets(),
            delta,
            "totalAssets"
        );
        assertApproxEqAbs(
            testConfig.asset.balanceOf(address(strategy)),
            0,
            delta,
            "asset balance"
        );
    }

    function testFail__unpause_nonOwner() public virtual {
        vm.prank(owner);
        strategy.pause();

        vm.prank(alice);
        strategy.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                              CLAIM
    //////////////////////////////////////////////////////////////*/

    /// @dev OPTIONAL -- Implement this if the strategy utilizes `claim()`
    function test__claim() public virtual {}

    /*//////////////////////////////////////////////////////////////
                              HARVEST
    //////////////////////////////////////////////////////////////*/

    /// @dev OPTIONAL -- Implement this if the strategy utilizes `harvest()`
    function test__harvest() public virtual {}

    /*//////////////////////////////////////////////////////////////
                              HARVEST CONFIG
    //////////////////////////////////////////////////////////////*/

    function test__setHarvestConfig() public virtual {}

    function test__setHarvestConfigOnlyOwner() public virtual {}

    /*//////////////////////////////////////////////////////////////
                              MIN TRADE AMOUNTS
    //////////////////////////////////////////////////////////////*/

    function test__setMinTradeAmounts() public virtual {}

    function test__setMinTradeAmountsOnlyOwner() public virtual {}
}
