// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { AaveV2Adapter, SafeERC20, IERC20, IERC20Metadata, Math, ILendingPool, IAaveMining, IAToken, IProtocolDataProvider, DataTypes, IStrategy, IWithRewards } from "../../../../../src/vault/adapter/aave/aaveV2/AaveV2Adapter.sol";
import { AaveV2TestConfigStorage, AaveV2TestConfig } from "./AaveV2TestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage, IAdapter } from "../../abstract/AbstractAdapterTest.sol";
import { MockStrategyClaimer } from "../../../../utils/mocks/MockStrategyClaimer.sol";

contract AaveV2AdapterTest is AbstractAdapterTest {
  using Math for uint256;

  ILendingPool lendingPool;
  IAaveMining aaveMining;
  IAToken aToken;

  function setUp() public {
    uint256 forkId = vm.createSelectFork(vm.rpcUrl("polygon"));
    vm.selectFork(forkId);

    testConfigStorage = ITestConfigStorage(address(new AaveV2TestConfigStorage()));

    _setUpTest(testConfigStorage.getTestConfig(0));
  }

  function overrideSetup(bytes memory testConfig) public override {
    _setUpTest(testConfig);
  }

  function _setUpTest(bytes memory testConfig) internal {
    (address _asset, address aaveDataProvider) = abi.decode(testConfig, (address, address));
    (address _aToken, , ) = IProtocolDataProvider(aaveDataProvider).getReserveTokensAddresses(_asset);

    aToken = IAToken(_aToken);
    lendingPool = ILendingPool(aToken.POOL());
    aaveMining = IAaveMining(aToken.getIncentivesController());

    setUpBaseTest(IERC20(_asset), address(new AaveV2Adapter()), aaveDataProvider, 10, "AaveV2 ", true);

    vm.label(address(aToken), "aToken");
    vm.label(address(lendingPool), "lendingPool");
    vm.label(address(aaveMining), "aaveMining");
    vm.label(address(asset), "asset");
    vm.label(address(this), "test");

    adapter.initialize(abi.encode(asset, address(this), strategy, 0, sigs, ""), externalRegistry, "");
  }

  /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

  function increasePricePerShare(uint256 amount) public override {
    deal(address(asset), address(aToken), asset.balanceOf(address(aToken)) + amount);
  }

  function iouBalance() public view override returns (uint256) {
    return aToken.balanceOf(address(adapter));
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
    assertEq(adapter.asset(), aToken.UNDERLYING_ASSET_ADDRESS(), "asset");
    assertEq(
      IERC20Metadata(address(adapter)).name(),
      string.concat("VaultCraft AaveV2 ", IERC20Metadata(address(asset)).name(), " Adapter"),
      "name"
    );
    assertEq(
      IERC20Metadata(address(adapter)).symbol(),
      string.concat("vcAv2-", IERC20Metadata(address(asset)).symbol()),
      "symbol"
    );

    assertEq(asset.allowance(address(adapter), address(lendingPool)), type(uint256).max, "allowance");
  }

  /*//////////////////////////////////////////////////////////////
                              CLAIM
    //////////////////////////////////////////////////////////////*/

    // Cant test claim for Aave since they diabled it. Geist a fork of Aave uses a slightly different interface on the Mining contract. 
}
