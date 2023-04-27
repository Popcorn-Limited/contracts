// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {EllipsisLpStakingAdapter, SafeERC20, IERC20, IERC20Metadata, Math, ILpStaking} from "../../../../../src/vault/adapter/ellipsis/lpStaking/EllipsisLpStakingAdapter.sol";
import {EllipsisLpStakingTestConfigStorage, EllipsisLpStakingTestConfig} from "./EllipsisLpStakingTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../../abstract/AbstractAdapterTest.sol";

contract EllipsisLpStakingAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    ILpStaking lpStaking =
        ILpStaking(0x5B74C99AA2356B4eAa7B85dC486843eDff8Dfdbe);

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("binance"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new EllipsisLpStakingTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));

        maxAssets = maxAssets / 100;
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _asset, uint256 _pId) = abi.decode(
            testConfig,
            (address, uint256)
        );

        setUpBaseTest(
            IERC20(_asset),
            address(new EllipsisLpStakingAdapter()),
            address(lpStaking),
            10,
            "Ellipsis ",
            true
        );

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            abi.encode(_pId)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
  //////////////////////////////////////////////////////////////*/

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        // Make sure totalAssets isn't 0
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

    function verify_adapterInit() public override {
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "Vaultcraft Ellipsis ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcE-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSE TESTS
  //////////////////////////////////////////////////////////////*/

    function test__unpause() public override {
        _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalSupply = adapter.totalSupply();
        uint256 oldIouBalance = iouBalance();

        adapter.pause();
        adapter.unpause();

        // We simply deposit back into the external protocol
        // TotalSupply and Assets dont change
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

    /*//////////////////////////////////////////////////////////////
                            CLAIM / HARVEST TESTS
  //////////////////////////////////////////////////////////////*/

    function test__harvest() public override {}
}
