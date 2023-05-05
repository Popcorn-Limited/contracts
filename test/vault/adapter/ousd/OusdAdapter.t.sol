// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { OusdAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IStrategy, IAdapter, IWithRewards, IERC4626 } from "../../../../src/vault/adapter/ousd/OusdAdapter.sol";
import { OusdTestConfigStorage, OusdTestConfig } from "./OusdTestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage } from "../abstract/AbstractAdapterTest.sol";
import { MockStrategyClaimer } from "../../../utils/mocks/MockStrategyClaimer.sol";

contract OusdAdapterTest is AbstractAdapterTest {
  using Math for uint256;

  IERC4626 public wOusd;
  address ousdWhale = 0x70fCE97d671E81080CA3ab4cc7A59aAc2E117137;

  function setUp() public {
    uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
    vm.selectFork(forkId);

    testConfigStorage = ITestConfigStorage(address(new OusdTestConfigStorage()));

    _setUpTest(testConfigStorage.getTestConfig(0));
  }

  function overrideSetup(bytes memory testConfig) public override {
    _setUpTest(testConfig);
  }

  function _setUpTest(bytes memory testConfig) internal {
    address _wOusd = abi.decode(testConfig, (address));

    wOusd = IERC4626(_wOusd);
    asset = IERC20(wOusd.asset());

    setUpBaseTest(IERC20(asset), address(new OusdAdapter()), address(wOusd), 10, "Ousd", true);

    vm.label(address(wOusd), "wOusd");
    vm.label(address(asset), "asset");
    vm.label(address(this), "test");

    adapter.initialize(abi.encode(asset, address(this), strategy, 0, sigs, ""), externalRegistry, testConfig);

    defaultAmount = 1e18;

    raise = 1000e18;
    maxAssets = defaultAmount * 1000;
    maxShares = 100e27;
  }

  /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

  function test__nothing() public {}

  function _mintAsset(uint256 amount, address receiver) internal override {
    vm.prank(ousdWhale);
    IERC20(asset).transfer(receiver, amount + 1);
  }

  function increasePricePerShare(uint256 amount) public override {
    vm.prank(0x89eBCb7714bd0D2F33ce3a35C12dBEB7b94af169);
    IERC20(address(wOusd)).transfer(address(adapter), amount);
  }

  // Verify that totalAssets returns the expected amount
  function verify_totalAssets() public override {
    _mintAsset(defaultAmount, bob);
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
      string.concat("VaultCraft Ousd ", IERC20Metadata(address(asset)).name(), " Adapter"),
      "name"
    );
    assertEq(
      IERC20Metadata(address(adapter)).symbol(),
      string.concat("vcO-", IERC20Metadata(address(asset)).symbol()),
      "symbol"
    );

    assertEq(asset.allowance(address(adapter), address(wOusd)), type(uint256).max, "allowance");
  }
}
