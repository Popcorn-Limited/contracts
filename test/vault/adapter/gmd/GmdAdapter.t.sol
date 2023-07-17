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
        raise = defaultAmount * 100_000;

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
                              HARVEST
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public override {
        // There is no call in gmd or glp to the balanceOf call to increase share price
        // Any price adjustments either come from external oracles or state changes that we cant influence
        // Therefore we cant test the harvest function
    }

    /*//////////////////////////////////////////////////////////////
                              PAUSE
    //////////////////////////////////////////////////////////////*/

    function test__unpause() public override {
        _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();
        uint256 oldIouBalance = iouBalance();

        adapter.pause();
        adapter.unpause();

        // We simply deposit back into the external protocol
        // TotalSupply and Assets dont change
        assertApproxEqRel(
            oldTotalAssets,
            adapter.totalAssets(),
            0.05e18,
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
        assertApproxEqRel(iouBalance(), oldIouBalance, 0.05e18, "iou balance");

        // Deposit and mint dont revert
        vm.startPrank(bob);
        adapter.deposit(defaultAmount, bob);
        adapter.mint(defaultAmount * 1e9, bob);
    }
}
