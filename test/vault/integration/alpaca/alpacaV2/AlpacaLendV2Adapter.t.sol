// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {AlpacaLendV2Adapter, SafeERC20, IERC20, IERC20Metadata, Math, IAlpacaLendV2Vault, IStrategy, IAdapter, IWithRewards, IAlpacaLendV2Vault, IAlpacaLendV2Manger, IAlpacaLendV2MiniFL, IAlpacaLendV2IbToken} from "../../../../../src/vault/adapter/alpaca/alpacaLendV2/AlpacaLendV2Adapter.sol";
import {AlpacaLendV2TestConfigStorage, AlpacaLendV2TestConfig} from "./AlpacaLendV2TestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage} from "../../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../../utils/mocks/MockStrategyClaimer.sol";

contract AlpacaLendV2AdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IAlpacaLendV2Manger alpacaManager =
        IAlpacaLendV2Manger(0xD20B887654dB8dC476007bdca83d22Fa51e93407);
    IAlpacaLendV2MiniFL miniFL;
    IAlpacaLendV2IbToken ibToken;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("bnb_smart_chain"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new AlpacaLendV2TestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        uint256 _pid = abi.decode(testConfig, (uint256));

        miniFL = IAlpacaLendV2MiniFL(alpacaManager.miniFL());
        ibToken = IAlpacaLendV2IbToken(miniFL.stakingTokens(_pid));
        asset = IERC20(ibToken.asset());

        setUpBaseTest(
            IERC20(asset),
            address(new AlpacaLendV2Adapter()),
            address(alpacaManager),
            10,
            "AlpacaLendV2",
            true
        );

        vm.label(address(alpacaManager), "AlpacaManager");
        vm.label(address(miniFL), "miniFL");
        vm.label(address(asset), "asset");
        vm.label(address(ibToken), "ibToken");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
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
        assertEq(adapter.asset(), address(asset), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft AlpacaLendV2 ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcAlV2-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(alpacaManager)),
            type(uint256).max,
            "allowance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                              HARVEST
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public virtual override {
        uint256 performanceFee = 1e16;
        uint256 hwm = 1e9;

        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        adapter.setPerformanceFee(performanceFee);
        increasePricePerShare(raise);

        uint256 gain = ((adapter.convertToAssets(1e18) +
            1 -
            adapter.highWaterMark()) * adapter.totalSupply()) / 1e18;
        uint256 fee = (gain * performanceFee) / 1e18;

        uint256 expectedFee = adapter.convertToShares(fee);

        vm.expectEmit(false, false, false, true, address(adapter));

        emit Harvested();

        adapter.harvest();

        // Multiply with the decimal offset
        assertApproxEqAbs(
            adapter.totalSupply(),
            defaultAmount * 1e9 + expectedFee,
            _delta_,
            "totalSupply"
        );
        assertApproxEqAbs(
            adapter.balanceOf(feeRecipient),
            expectedFee,
            _delta_,
            "expectedFee"
        );
    }
}
