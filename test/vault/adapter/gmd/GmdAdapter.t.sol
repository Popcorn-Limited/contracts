// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {GmdTestConfigStorage, GmdTestConfig} from "./GmdTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";
import {GmdAdapter, IGmdVault, SafeERC20, IERC20, IERC20Metadata, Math} from "../../../../src/vault/adapter/gmd/GmdAdapter.sol";

contract GmdAdapterTest is AbstractAdapterTest {
    using Math for uint256;
    IGmdVault public gmdVault;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("arbitrum"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new GmdTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _asset, address _vault, uint256 _poolId) = abi.decode(
            testConfig,
            (address, address, uint256)
        );

        setUpBaseTest(
            IERC20(_asset),
            address(new GmdAdapter()),
            _vault,
            10,
            "Gmd ",
            false
        );

        gmdVault = IGmdVault(_vault);

        vm.label(address(gmdVault), "gmdVault");
        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), address(0), 0, sigs, ""),
            externalRegistry,
            abi.encode(_poolId)
        );

        defaultAmount = 10 ** IERC20Metadata(_asset).decimals();
        minFuzz = defaultAmount;
        minShares = defaultAmount * 1e9;
        raise = defaultAmount;

        maxAssets = defaultAmount * 10;
        maxShares = minShares * 10;
    }

    /*//////////////////////////////////////////////////////////////
                         INITIALIZATION
   //////////////////////////////////////////////////////////////*/
    function test__initialization() public override {
        ITestConfigStorage testConfigStorage = ITestConfigStorage(
            address(new GmdTestConfigStorage())
        );
        bytes memory testConfig = testConfigStorage.getTestConfig(0);

        (address _asset, address _vault, uint256 _poolId) = abi.decode(
            testConfig,
            (address, address, uint256)
        );

        createAdapter();
        uint256 callTime = block.timestamp;

        vm.expectEmit(false, false, false, true, address(adapter));
        emit Initialized(uint8(1));

        adapter.initialize(
            abi.encode(asset, address(this), address(0), 0, sigs, ""),
            externalRegistry,
            abi.encode(_poolId)
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
        IGmdVault.PoolInfo memory poolInfo = gmdVault.poolInfo(0);
        assertEq(adapter.asset(), poolInfo.lpToken, "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft GMD ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcGMD-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(gmdVault)),
            type(uint256).max,
            "allowance"
        );

        // Revert if MaxLoss is too high
        createAdapter();
        adapter.initialize(
            abi.encode(asset, address(this), address(0), 0, sigs, ""),
            externalRegistry,
            abi.encode(0)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function increasePricePerShare(uint256 amount) public override {
        deal(
            address(asset),
            address(gmdVault),
            asset.balanceOf(address(gmdVault)) + amount
        );
    }

    function iouBalance() public view override returns (uint256) {
        IGmdVault.PoolInfo memory poolInfo = gmdVault.poolInfo(0);
        return IERC20(poolInfo.GDlptoken).balanceOf(address(adapter));
    }

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        deal(address(asset), bob, defaultAmount);
        vm.startPrank(bob);
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, bob);
        vm.stopPrank();

        assertApproxEqAbs(
            adapter.totalAssets(),
            adapter.convertToAssets(adapter.totalSupply()),
            _delta_,
            string.concat("totalSupply converted != totalAssets", baseTestId)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
    //////////////////////////////////////////////////////////////*/
    // NOTE - The yearn adapter suffers often from an off-by-one error which "steals" 1 wei from the user
    // function test__RT_deposit_withdraw() public override {
    //     _mintAssetAndApproveForAdapter(minFuzz, bob);

    //     vm.startPrank(bob);
    //     uint256 shares1 = adapter.deposit(1000000, bob);
    //     uint256 shares2 = adapter.withdraw(500000, bob, bob);
    //     vm.stopPrank();

    //     // We compare assets here with maxWithdraw since the shares of withdraw will always be lower than `compoundDefaultAmount`
    //     // This tests the same assumption though. As long as you can withdraw less or equal assets to the input amount you cant round trip
    //     //assertGe(minFuzz, adapter.maxWithdraw(bob), testId);
    // }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/MINT/WITHDRAW/REDEEM
    //////////////////////////////////////////////////////////////*/
    // function test__mint(uint8 fuzzAmount) public override {
    //     uint8 len = uint8(testConfigStorage.getTestConfigLength());
    //     for (uint8 i; i < len; i++) {
    //         if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));
    //         uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);

    //         _mintAssetAndApproveForAdapter(adapter.previewMint(amount), bob);

    //         prop_mint(bob, bob, amount, testId);

    //         increasePricePerShare(raise);

    //         _mintAssetAndApproveForAdapter(adapter.previewMint(amount), bob);

    //         prop_mint(bob, alice, amount, testId);
    //     }
    // }

    // function test__withdraw(uint8 fuzzAmount) public override {
    //     uint256 amount = 10000000;//1e18;

    //     uint8 len = uint8(testConfigStorage.getTestConfigLength());
    //     for (uint8 i; i < len; i++) {
    //         if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

    //         uint256 reqAssets = adapter.previewMint(
    //             adapter.previewWithdraw(amount)
    //         ) * 10;
    //         _mintAssetAndApproveForAdapter(reqAssets, bob);
    //         vm.prank(bob);
    //         adapter.deposit(reqAssets, bob);

    //         prop_withdraw(bob, bob, amount / 10, testId);

    //         _mintAssetAndApproveForAdapter(reqAssets, bob);
    //         vm.prank(bob);
    //         adapter.deposit(reqAssets, bob);

    //         increasePricePerShare(raise);

    //         vm.prank(bob);
    //         adapter.approve(alice, type(uint256).max);

    //         prop_withdraw(alice, bob, amount, testId);
    //     }
    // }

    // /*//////////////////////////////////////////////////////////////
    //                       PREVIEW VIEWS
    // //////////////////////////////////////////////////////////////*/
    // function test__previewDeposit(uint8 fuzzAmount) public override {
    //     uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

    //     _mintAsset(maxAssets, bob);
    //     vm.prank(bob);
    //     asset.approve(address(adapter), maxAssets);
    //     amount = 100000000;

    //     prop_previewDeposit(bob, bob, amount, testId);
    // }

    // function test__previewWithdraw(uint8 fuzzAmount) public override {
    //     uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

    //     uint256 reqAssets = adapter.previewMint(
    //         adapter.previewWithdraw(amount)
    //     ) * 10;
    //     _mintAssetAndApproveForAdapter(reqAssets, bob);
    //     vm.prank(bob);
    //     adapter.deposit(100000000, bob);
    //     amount = 100000;

    //     prop_previewWithdraw(bob, bob, bob, amount, testId);
    // }

    /*//////////////////////////////////////////////////////////////
                          HARVEST
    //////////////////////////////////////////////////////////////*/

    // function test__harvest() public override {
    //     uint256 performanceFee = 1e16;
    //     uint256 hwm = 1e9;

    //     _mintAssetAndApproveForAdapter(defaultAmount, bob);

    //     vm.prank(bob);
    //     adapter.deposit(defaultAmount, bob);

    //     uint256 oldTotalAssets = adapter.totalAssets();
    //     adapter.setPerformanceFee(performanceFee);
    //     increasePricePerShare(raise);
    //     vm.warp(block.timestamp + 100);

    //     uint256 gain = ((
    //         adapter.highWaterMark() - adapter.convertToAssets(1e18)) * adapter.totalSupply()) / 1e18;

    //     uint256 fee = (gain * performanceFee) / 1e18;

    //     uint256 expectedFee = adapter.convertToShares(fee);

    //     vm.expectEmit(false, false, false, true, address(adapter));

    //     emit Harvested();

    //     adapter.harvest();

    //     // Multiply with the decimal offset
    //     assertApproxEqAbs(
    //         adapter.totalSupply(),
    //         defaultAmount * 1e9 ,
    //         _delta_,
    //         "totalSupply"
    //     );

    //     assertApproxEqAbs(
    //         adapter.balanceOf(feeRecipient),
    //         0,
    //         _delta_,
    //         "expectedFee"
    //     );
    // }

    /*//////////////////////////////////////////////////////////////
                              PAUSE
    //////////////////////////////////////////////////////////////*/

    // function test__unpause() public override {
    //     uint defaultAmount = 1000000000;
    //     _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);

    //     vm.prank(bob);
    //     adapter.deposit(defaultAmount, bob);

    //     uint256 oldTotalAssets = adapter.totalAssets();
    //     uint256 oldTotalSupply = adapter.totalSupply();
    //     uint256 oldIouBalance = iouBalance();

    //     adapter.pause();
    //     adapter.unpause();

    //     // We simply deposit back into the external protocol
    //     // TotalSupply and Assets dont change
    //     // @dev overriden _delta_
    //     assertApproxEqAbs(oldTotalAssets, adapter.totalAssets(), 5e6, "totalAssets");
    //     assertApproxEqAbs(oldTotalSupply, adapter.totalSupply(), 50, "totalSupply");
    //     assertApproxEqAbs(asset.balanceOf(address(adapter)), 0, 50, "asset balance");
    //     assertApproxEqRel(iouBalance(), oldIouBalance, 4e18, "iou balance");

    //     // Deposit and mint dont revert
    //     vm.startPrank(bob);
    //     adapter.deposit(defaultAmount, bob);
    //     //adapter.mint(defaultAmount, bob);
    // }
}
