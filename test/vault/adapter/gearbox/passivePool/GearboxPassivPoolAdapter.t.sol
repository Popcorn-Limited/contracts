// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { GearboxPassivePoolAdapter, SafeERC20, IERC20, IERC20Metadata, IAddressProvider, IContractRegistry, IPoolService } from "../../../../../src/vault/adapter/gearbox/passivePool/GearboxPassivePoolAdapter.sol";
import { GearboxPassivePoolTestConfigStorage, GearboxPassivePoolTestConfig } from "./GearboxPassivePoolTestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage, IAdapter } from "../../abstract/AbstractAdapterTest.sol";

interface IBurnable {
  function burn(address from, uint256 amount) external;
}

contract GearboxPassivePoolAdapterTest is AbstractAdapterTest {
  IAddressProvider addressProvider = IAddressProvider(0xcF64698AFF7E5f27A11dff868AF228653ba53be0);
  IPoolService poolService;
  IERC20 dieselToken;

  function setUp() public {
    uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
    vm.selectFork(forkId);

    testConfigStorage = ITestConfigStorage(address(new GearboxPassivePoolTestConfigStorage()));

    _setUpTest(testConfigStorage.getTestConfig(0));
  }

  function overrideSetup(bytes memory testConfig) public override {
    _setUpTest(testConfig);
  }

  function _setUpTest(bytes memory testConfig) internal {
    uint256 _pid = abi.decode(testConfig, (uint256));

    poolService = IPoolService(IContractRegistry(addressProvider.getContractsRegister()).pools(_pid));
    dieselToken = IERC20(poolService.dieselToken());

    setUpBaseTest(
      IERC20(poolService.underlyingToken()),
      address(new GearboxPassivePoolAdapter()),
      address(addressProvider),
      10,
      "Gearbox PP ",
      false
    );

    vm.label(address(poolService), "poolService");
    vm.label(address(asset), "asset");
    vm.label(address(this), "test");

    adapter.initialize(abi.encode(asset, address(this), address(0), 0, sigs, ""), externalRegistry, testConfig);

    defaultAmount = 10 ** IERC20Metadata(address(asset)).decimals();

    raise = defaultAmount;
    maxAssets = defaultAmount * 1000;
    maxShares = maxAssets / 2;
  }

  /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

  function increasePricePerShare(uint256) public override {
    // DieselToken value can only be increased by reducing the supply of dieselToken or increasing time to accrue interest
    vm.prank(address(poolService));
    IBurnable(address(dieselToken)).burn(0x5EC6abfF9BB4c673f63D077a962A29945f744857, 1000e18);
  }

  function iouBalance() public view override returns (uint256) {
    return dieselToken.balanceOf(address(adapter));
  }

  /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

  function verify_adapterInit() public override {
    assertEq(adapter.asset(), poolService.underlyingToken(), "asset");
    assertEq(
      IERC20Metadata(address(adapter)).name(),
      string.concat("VaultCraft GearboxPassivePool ", IERC20Metadata(address(asset)).name(), " Adapter"),
      "name"
    );
    assertEq(
      IERC20Metadata(address(adapter)).symbol(),
      string.concat("vcGPP-", IERC20Metadata(address(asset)).symbol()),
      "symbol"
    );

    assertEq(asset.allowance(address(adapter), address(poolService)), type(uint256).max, "allowance");
  }

  /*//////////////////////////////////////////////////////////////
                          TOTAL ASSETS
    //////////////////////////////////////////////////////////////*/

  // Verify that totalAssets returns the expected amount
  function verify_totalAssets() public override {
    // Make sure totalAssets isnt 0
    _mintAsset(defaultAmount, bob);

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

    assertApproxEqAbs(
      adapter.totalAssets(),
      poolService.fromDiesel(iouBalance()),
      _delta_,
      string.concat("totalAssets != pool assets", baseTestId)
    );
  }
}
