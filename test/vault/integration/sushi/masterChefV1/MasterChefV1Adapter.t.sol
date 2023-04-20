// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { MasterChefV1Adapter, SafeERC20, IERC20, IERC20Metadata, Math, IMasterChefV1, IStrategy, IAdapter, IWithRewards } from "../../../../../../src/vault/adapter/sushi/masterChefV1/MasterChefV1Adapter.sol";
import { MasterChefV1TestConfigStorage, MasterChefV1TestConfig } from "./MasterChefV1TestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage } from "../../abstract/AbstractAdapterTest.sol";
import { MockStrategyClaimer } from "../../../../utils/mocks/MockStrategyClaimer.sol";

contract MasterChefV1AdapterTest is AbstractAdapterTest {
  using Math for uint256;

  IMasterChefV1 public MasterChefV1 = IMasterChefV1(0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd);

  address public rewardsToken;
  uint256 pid;

  function setUp() public {
    uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
    vm.selectFork(forkId);

    testConfigStorage = ITestConfigStorage(address(new MasterChefV1TestConfigStorage()));

    _setUpTest(testConfigStorage.getTestConfig(0));
  }

  function overrideSetup(bytes memory testConfig) public override {
    _setUpTest(testConfig);
  }

  function _setUpTest(bytes memory testConfig) internal {
    (uint256 _pid, address _rewardsToken) = abi.decode(testConfig, (uint256, address));

    pid = _pid;
    rewardsToken = _rewardsToken;
    IMasterChefV1.PoolInfo memory info = MasterChefV1.poolInfo(_pid);

    setUpBaseTest(
      IERC20(info.lpToken),
      address(new MasterChefV1Adapter()),
      address(MasterChefV1),
      10,
      "MasterChefV1",
      true
    );

    vm.label(address(MasterChefV1), "MasterChefV1");
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
      string.concat("VaultCraft MasterChefV1 ", IERC20Metadata(address(asset)).name(), " Adapter"),
      "name"
    );
    assertEq(
      IERC20Metadata(address(adapter)).symbol(),
      string.concat("vcMcV1-", IERC20Metadata(address(asset)).symbol()),
      "symbol"
    );

    assertEq(asset.allowance(address(adapter), address(MasterChefV1)), type(uint256).max, "allowance");
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

    vm.roll(block.number + 30);
    vm.warp(block.timestamp + 2);

    vm.prank(bob);
    adapter.withdraw(0, bob, bob);

    address[] memory rewardTokens = IWithRewards(address(adapter)).rewardTokens();
    assertEq(rewardTokens[0], rewardsToken);

    assertGt(IERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2).balanceOf(address(adapter)), 0);
  }
}
