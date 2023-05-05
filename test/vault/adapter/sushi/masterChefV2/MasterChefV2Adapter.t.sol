// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { MasterChefV2Adapter, SafeERC20, IERC20, IERC20Metadata, Math, IMasterChefV2, IStrategy, IAdapter, IWithRewards } from "../../../../../../src/vault/adapter/sushi/masterChefV2/MasterChefV2Adapter.sol";
import { MasterChefV2TestConfigStorage, MasterChefV2TestConfig } from "./MasterChefV2TestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage } from "../../abstract/AbstractAdapterTest.sol";
import { MockStrategyClaimer } from "../../../../utils/mocks/MockStrategyClaimer.sol";

contract MasterChefV2AdapterTest is AbstractAdapterTest {
  using Math for uint256;

  IMasterChefV2 public masterChef = IMasterChefV2(0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d);

  address public rewardsToken;
  uint256 pid;

  function setUp() public {
    uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
    vm.selectFork(forkId);

    testConfigStorage = ITestConfigStorage(address(new MasterChefV2TestConfigStorage()));

    _setUpTest(testConfigStorage.getTestConfig(0));
  }

  function overrideSetup(bytes memory testConfig) public override {
    _setUpTest(testConfig);
  }

  function _setUpTest(bytes memory testConfig) internal {
    (uint256 _pid, address _rewardsToken) = abi.decode(testConfig, (uint256, address));

    pid = _pid;
    rewardsToken = _rewardsToken;

    setUpBaseTest(
      IERC20(masterChef.lpToken(_pid)),
      address(new MasterChefV2Adapter()),
      address(masterChef),
      10,
      "MasterChefV2",
      true
    );

    vm.label(address(masterChef), "MasterChefV2");
    vm.label(address(asset), "asset");
    vm.label(address(this), "test");

    adapter.initialize(abi.encode(asset, address(this), strategy, 0, sigs, ""), externalRegistry, testConfig);
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
      string.concat("VaultCraft MasterChefV2 ", IERC20Metadata(address(asset)).name(), " Adapter"),
      "name"
    );
    assertEq(
      IERC20Metadata(address(adapter)).symbol(),
      string.concat("vcMcV2-", IERC20Metadata(address(asset)).symbol()),
      "symbol"
    );

    assertEq(asset.allowance(address(adapter), address(masterChef)), type(uint256).max, "allowance");
  }

  /*//////////////////////////////////////////////////////////////
                              CLAIM
    //////////////////////////////////////////////////////////////*/

  function test__claim() public override {
    strategy = IStrategy(address(new MockStrategyClaimer()));
    createAdapter();
    adapter.initialize(
      abi.encode(asset, address(this), strategy, 0, sigs, ""),
      externalRegistry,
      testConfigStorage.getTestConfig(0)
    );

    _mintAssetAndApproveForAdapter(1000e18, bob);

    vm.prank(bob);
    adapter.deposit(1000e18, bob);

    vm.roll(block.number + 3000);
    vm.warp(block.timestamp + 200);

    vm.prank(bob);
    adapter.withdraw(1, bob, bob);

    address[] memory rewardTokens = IWithRewards(address(adapter)).rewardTokens();
    assertEq(rewardTokens[0], rewardsToken);

    assertGt(IERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2).balanceOf(address(adapter)), 0);
    assertGt(IERC20(0x471Ea49dd8E60E697f4cac262b5fafCc307506e4).balanceOf(address(adapter)), 0);
  }
}
