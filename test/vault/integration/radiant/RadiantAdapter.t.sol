// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {RadiantAdapter, SafeERC20, IERC20, IERC20Metadata, Math, ILendingPool, IRToken, IProtocolDataProvider, IIncentivesController, IRewardMinter, IMiddleFeeDistributor, DataTypes, IStrategy, IWithRewards} from "../../../../src/vault/adapter/radiant/RadiantAdapter.sol";
import {RadiantTestConfigStorage, RadiantTestConfig} from "./RadiantTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../utils/mocks/MockStrategyClaimer.sol";

contract RadiantAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    ILendingPool lendingPool;
    IIncentivesController controller;
    IRToken rToken;

    IRewardMinter minter;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("arbitrum"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new RadiantTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _asset, address radiantDataProvider) = abi.decode(
            testConfig,
            (address, address)
        );
        (address _rToken, , ) = IProtocolDataProvider(radiantDataProvider)
            .getReserveTokensAddresses(_asset);

        rToken = IRToken(_rToken);
        lendingPool = ILendingPool(rToken.POOL());

        controller = IIncentivesController(rToken.getIncentivesController());
        IRewardMinter minter = IRewardMinter(controller.rewardMinter());

        setUpBaseTest(
            IERC20(_asset),
            address(new RadiantAdapter()),
            radiantDataProvider,
            10,
            "Radiant ",
            true
        );

        vm.label(address(rToken), "rToken");
        vm.label(address(lendingPool), "lendingPool");
        vm.label(address(controller), "controller");
        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            ""
        );
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function increasePricePerShare(uint256 amount) public override {
        deal(
            address(asset),
            address(rToken),
            asset.balanceOf(address(rToken)) + amount
        );
    }

    function iouBalance() public view override returns (uint256) {
        return rToken.balanceOf(address(adapter));
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

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), rToken.UNDERLYING_ASSET_ADDRESS(), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Radiant ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcRdt-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(lendingPool)),
            type(uint256).max,
            "allowance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                              CLAIM
    //////////////////////////////////////////////////////////////*/
}
