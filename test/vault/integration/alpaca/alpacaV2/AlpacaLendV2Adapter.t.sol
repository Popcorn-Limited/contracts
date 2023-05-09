// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {AlpacaLendV2Adapter, SafeERC20, IERC20, IERC20Metadata, Math, IAlpacaLendV2Vault, IStrategy, IAdapter, IWithRewards, IAlpacaLendV2Vault, IAlpacaLendV2Manger, IAlpacaLendV2MiniFL, IAlpacaLendV2IbToken} from "../../../../../src/vault/adapter/alpaca/alpacaLendV2/AlpacaLendV2Adapter.sol";
import {AlpacaLendV2TestConfigStorage, AlpacaLendV2TestConfig} from "./AlpacaLendV2TestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage} from "../../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../../utils/mocks/MockStrategyClaimer.sol";

contract AlpacaLendV2AdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IAlpacaLendV2Manger alpacaManager;
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
        (address _manager, uint256 _pid) = abi.decode(
            testConfig,
            (address, uint256)
        );

        alpacaManager = IAlpacaLendV2Manger(_manager);
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
                    DEPOSIT/MINT/WITHDRAW/REDEEM
    //////////////////////////////////////////////////////////////*/

    function test__deposit(uint8 fuzzAmount) public virtual override {
        uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

            _mintAssetAndApproveForAdapter(amount, bob);

            prop_deposit(bob, bob, amount, testId);

            increasePricePerShare(raise);

            _mintAssetAndApproveForAdapter(amount, bob);
            prop_deposit(bob, alice, amount, testId);
        }
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
}
