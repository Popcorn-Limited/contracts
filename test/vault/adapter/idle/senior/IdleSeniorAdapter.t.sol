// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {IdleSeniorAdapter, SafeERC20, IERC20, IERC20Metadata, IStrategy, ERC20, IIdleCDO} from "../../../../../src/vault/adapter/idle/senior/IdleSeniorAdapter.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter, Math} from "../../abstract/AbstractAdapterTest.sol";
import {IdleTestConfigStorage, IdleTestConfig} from "../IdleTestConfigStorage.sol";
import {MockStrategyClaimer} from "../../../../utils/mocks/MockStrategyClaimer.sol";

contract IdleSeniorAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    address registry = 0x84FDeE80F18957A041354E99C7eB407467D94d8E; // Registry
    IIdleCDO public cdo;
    address tranch;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new IdleTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        address _cdo = abi.decode(testConfig, (address));

        cdo = IIdleCDO(_cdo);
        address token = cdo.token();
        tranch = cdo.AATranche();

        setUpBaseTest(
            IERC20(token),
            address(new IdleSeniorAdapter()),
            registry,
            10,
            "IDLE ",
            true
        );

        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );
        if (defaultAmount > adapter.maxDeposit(address(this))) {
            defaultAmount = adapter.maxDeposit(address(this)) / 1000;
        }
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
  //////////////////////////////////////////////////////////////*/

    function increasePricePerShare(uint256 amount) public override {
        deal(
            tranch,
            address(adapter),
            IERC20(tranch).balanceOf(address(adapter)) + amount
        );
    }

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        // Make sure totalAssets isnt 0
        deal(address(asset), bob, defaultAmount);
        vm.startPrank(bob);
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, bob);
        vm.stopPrank();

        assertEq(
            adapter.totalAssets(),
            adapter.convertToAssets(adapter.totalSupply()),
            string.concat("totalSupply converted != totalAssets", baseTestId)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        createAdapter();
        uint256 callTime = block.timestamp;

        vm.expectEmit(false, false, false, true, address(adapter));
        emit Initialized(uint8(1));
        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfigStorage.getTestConfig(0)
        );
        assertEq(adapter.owner(), address(this), "owner");
        assertEq(adapter.strategy(), address(strategy), "strategy");
        assertEq(adapter.harvestCooldown(), 0, "harvestCooldown");
        assertEq(adapter.strategyConfig(), "", "strategyConfig");
        assertEq(
            IERC20Metadata(address(adapter)).decimals(),
            IERC20Metadata(address(asset)).decimals() + adapter.decimalOffset(),
            "decimals"
        );
        verify_adapterInit();
    }

    function verify_adapterInit() public override {
        // assertNotEq(IEllipsisLpStaking(lpStaking).depositTokens(adapter.asset()), address(0), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Idle Senior ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcIdlS-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );
    }

    function test__previewWithdraw(uint8 fuzzAmount) public override {
        uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

        uint256 reqAssets = adapter.previewMint(
            adapter.previewWithdraw(amount)
        ) * 10;
        _mintAssetAndApproveForAdapter(reqAssets, bob);
        vm.prank(bob);
        adapter.deposit(reqAssets, bob);

        vm.roll(block.number + 1);

        prop_previewWithdraw(bob, bob, bob, amount, testId);
    }

    function test__previewRedeem(uint8 fuzzAmount) public override {
        uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);

        uint256 reqAssets = adapter.previewMint(amount) * 10;
        _mintAssetAndApproveForAdapter(reqAssets, bob);
        vm.prank(bob);
        adapter.deposit(reqAssets, bob);

        vm.roll(block.number + 1);

        prop_previewRedeem(bob, bob, bob, amount, testId);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/MINT/WITHDRAW/REDEEM
  //////////////////////////////////////////////////////////////*/

    function test__withdraw(uint8 fuzzAmount) public override {
        uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

            uint256 reqAssets = adapter.previewMint(
                adapter.previewWithdraw(amount)
            ) * 10;
            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);

            adapter.deposit(reqAssets, bob);
            vm.roll(block.number + 1);

            prop_withdraw(bob, bob, amount / 10, testId);

            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);

            adapter.deposit(reqAssets, bob);
            vm.roll(block.number + 1);

            increasePricePerShare(raise);

            vm.prank(bob);
            adapter.approve(alice, type(uint256).max);

            prop_withdraw(alice, bob, amount, testId);
        }
    }

    function test__redeem(uint8 fuzzAmount) public override {
        uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

            uint256 reqAssets = adapter.previewMint(amount) * 10;
            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);

            adapter.deposit(reqAssets, bob);
            vm.roll(block.number + 1);

            prop_redeem(bob, bob, amount, testId);

            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);

            adapter.deposit(reqAssets, bob);
            vm.roll(block.number + 1);

            increasePricePerShare(raise);

            vm.prank(bob);
            adapter.approve(alice, type(uint256).max);
            prop_redeem(alice, bob, amount, testId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
  //////////////////////////////////////////////////////////////*/

    function test__RT_deposit_redeem() public override {
        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.startPrank(bob);
        uint256 shares = adapter.deposit(defaultAmount, bob);

        vm.roll(block.number + 1);

        uint256 assets = adapter.redeem(adapter.maxRedeem(bob), bob, bob);
        vm.stopPrank();

        // Pass the test if maxRedeem is smaller than deposit since round trips are impossible
        if (adapter.maxRedeem(bob) == defaultAmount) {
            assertLe(assets, defaultAmount, testId);
        }
    }

    function test__RT_deposit_withdraw() public override {
        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.startPrank(bob);
        uint256 shares1 = adapter.deposit(defaultAmount, bob);

        vm.roll(block.number + 1);

        uint256 shares2 = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
        vm.stopPrank();

        // Pass the test if maxWithdraw is smaller than deposit since round trips are impossible
        if (adapter.maxWithdraw(bob) == defaultAmount) {
            assertGe(shares2, shares1, testId);
        }
    }

    function test__RT_mint_withdraw() public override {
        _mintAssetAndApproveForAdapter(adapter.previewMint(defaultAmount), bob);

        vm.startPrank(bob);
        uint256 assets = adapter.mint(defaultAmount, bob);

        vm.roll(block.number + 1);

        uint256 shares = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
        vm.stopPrank();

        if (adapter.maxWithdraw(bob) == assets) {
            assertGe(shares, defaultAmount, testId);
        }
    }

    function test__RT_mint_redeem() public override {
        _mintAssetAndApproveForAdapter(adapter.previewMint(defaultAmount), bob);

        vm.startPrank(bob);
        uint256 assets1 = adapter.mint(defaultAmount, bob);

        vm.roll(block.number + 1);

        uint256 assets2 = adapter.redeem(adapter.maxRedeem(bob), bob, bob);
        vm.stopPrank();

        if (adapter.maxRedeem(bob) == defaultAmount) {
            assertLe(assets2, assets1, testId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          MAX VIEWS
    //////////////////////////////////////////////////////////////*/

    // NOTE: These Are just prop tests currently. Override tests here if the adapter has unique max-functions which override AdapterBase.sol

    function test__maxDeposit() public override {
        prop_maxDeposit(bob);

        // Deposit smth so withdraw on pause is not 0
        _mintAsset(defaultAmount, address(this));
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, address(this));

        vm.roll(block.number + 1);
        adapter.pause();
        assertEq(adapter.maxDeposit(bob), 0);
    }

    function test__maxMint() public override {
        prop_maxMint(bob);

        // Deposit smth so withdraw on pause is not 0
        _mintAsset(defaultAmount, address(this));
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, address(this));

        vm.roll(block.number + 1);

        adapter.pause();
        assertEq(adapter.maxMint(bob), 0);
    }

    /*//////////////////////////////////////////////////////////////
                              PAUSE
    //////////////////////////////////////////////////////////////*/

    function test__pause() public override {
        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();

        vm.roll(block.number + 1);
        adapter.pause();

        // We simply withdraw into the adapter
        // TotalSupply and Assets dont change
        assertApproxEqAbs(
            oldTotalAssets,
            adapter.totalAssets(),
            _delta_,
            "totalAssets"
        );
        assertApproxEqAbs(
            oldTotalSupply,
            adapter.totalSupply(),
            _delta_,
            "totalSupply"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(adapter)),
            oldTotalAssets,
            _delta_,
            "asset balance"
        );
        assertApproxEqAbs(iouBalance(), 0, _delta_, "iou balance");

        vm.startPrank(bob);
        // Deposit and mint are paused (maxDeposit/maxMint are set to 0 on pause)
        vm.expectRevert();
        adapter.deposit(defaultAmount, bob);

        vm.expectRevert();
        adapter.mint(defaultAmount, bob);

        // Withdraw and Redeem dont revert
        adapter.withdraw(defaultAmount / 10, bob, bob);
        adapter.redeem(defaultAmount / 10, bob, bob);
    }

    function test__unpause() public override {
        _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();
        uint256 oldIouBalance = iouBalance();

        vm.roll(block.number + 1);
        adapter.pause();

        vm.roll(block.number + 1);
        adapter.unpause();

        // We simply deposit back into the external protocol
        // TotalSupply and Assets dont change
        assertApproxEqAbs(
            oldTotalAssets,
            adapter.totalAssets(),
            _delta_,
            "totalAssets"
        );
        assertApproxEqAbs(
            oldTotalSupply,
            adapter.totalSupply(),
            _delta_,
            "totalSupply"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(adapter)),
            0,
            _delta_,
            "asset balance"
        );
        assertApproxEqAbs(iouBalance(), oldIouBalance, _delta_, "iou balance");

        // Deposit and mint dont revert
        vm.startPrank(bob);
        adapter.deposit(defaultAmount, bob);
        adapter.mint(defaultAmount, bob);
    }
}
