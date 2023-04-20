// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { AaveV3Adapter, SafeERC20, IERC20, IERC20Metadata, Math, ILendingPool, IAaveIncentives, IAToken, IProtocolDataProvider, DataTypes } from "../../../../../src/vault/adapter/aave/aaveV3/AaveV3Adapter.sol";
import { AaveV3TestConfigStorage, AaveV3TestConfig } from "./AaveV3TestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage, IAdapter } from "../../abstract/AbstractAdapterTest.sol";

contract AaveV3AdapterTest is AbstractAdapterTest {
  using Math for uint256;

  ILendingPool lendingPool;
  IAaveIncentives aaveIncentives;
  IAToken aToken;

  function setUp() public {
    uint256 forkId = vm.createSelectFork(vm.rpcUrl("polygon"));
    vm.selectFork(forkId);

    testConfigStorage = ITestConfigStorage(address(new AaveV3TestConfigStorage()));

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
    aaveIncentives = IAaveIncentives(aToken.getIncentivesController());

    setUpBaseTest(IERC20(_asset), address(new AaveV3Adapter()), aaveDataProvider, 10, "AaveV2 ", true);

    vm.label(address(aToken), "aToken");
    vm.label(address(lendingPool), "lendingPool");
    vm.label(address(aaveIncentives), "aaveIncentives");
    vm.label(address(asset), "asset");
    vm.label(address(this), "test");

    adapter.initialize(abi.encode(asset, address(this), strategy, 0, sigs, ""), externalRegistry, "");

    defaultAmount = 10 ** IERC20Metadata(address(asset)).decimals();
    minFuzz = defaultAmount * 10;
    raise = defaultAmount * 100_000_000;
    maxAssets = defaultAmount * 100;
    maxShares = maxAssets / 2;
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
      string.concat("VaultCraft AaveV3 ", IERC20Metadata(address(asset)).name(), " Adapter"),
      "name"
    );
    assertEq(
      IERC20Metadata(address(adapter)).symbol(),
      string.concat("vcAv3-", IERC20Metadata(address(asset)).symbol()),
      "symbol"
    );

    assertEq(asset.allowance(address(adapter), address(lendingPool)), type(uint256).max, "allowance");
  }

  function getApy() public view returns (uint256) {
    DataTypes.ReserveData memory data = lendingPool.getReserveData(address(asset));
    uint128 supplyRate = data.currentLiquidityRate;
    return uint256(supplyRate / 1e9);
  }

  /*//////////////////////////////////////////////////////////////
                              CLAIM
    //////////////////////////////////////////////////////////////*/

  // Cant test claim for Aave since they dont use it yet.
}
