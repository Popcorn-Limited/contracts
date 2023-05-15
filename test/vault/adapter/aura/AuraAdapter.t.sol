// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { AuraAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IAuraBooster, IAuraRewards, IAuraStaking, IStrategy, IAdapter, IWithRewards } from "../../../../src/vault/adapter/aura/AuraAdapter.sol";
import { AuraTestConfigStorage, AuraTestConfig } from "./AuraTestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage } from "../abstract/AbstractAdapterTest.sol";
import { MockStrategyClaimer } from "../../../utils/mocks/MockStrategyClaimer.sol";

contract AuraAdapterTest is AbstractAdapterTest {
  using Math for uint256;

  IAuraBooster public auraBooster = IAuraBooster(0xA57b8d98dAE62B26Ec3bcC4a365338157060B234);
  IAuraRewards public auraRewards;
  IAuraStaking public auraStaking;

  address public auraLpToken;
  uint256 public pid;

  function setUp() public {
    uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
    vm.selectFork(forkId);

    testConfigStorage = ITestConfigStorage(address(new AuraTestConfigStorage()));

    _setUpTest(testConfigStorage.getTestConfig(0));
  }

  function overrideSetup(bytes memory testConfig) public override {
    _setUpTest(testConfig);
  }

  function _setUpTest(bytes memory testConfig) internal {
    uint256 _pid = abi.decode(testConfig, (uint256));

    pid = _pid;

    auraStaking = IAuraStaking(auraBooster.stakerRewards());

    (address balancerLpToken, address _auraLpToken, address _auraGauge, address _auraRewards, , ) = auraBooster
      .poolInfo(pid);

    auraRewards = IAuraRewards(_auraRewards);
    auraLpToken = _auraLpToken;

    setUpBaseTest(IERC20(balancerLpToken), address(new AuraAdapter()), address(auraBooster), 10, "Aura", true);

    vm.label(address(auraBooster), "auraBooster");
    vm.label(address(auraRewards), "auraRewards");
    vm.label(address(auraStaking), "auraStaking");
    vm.label(address(auraLpToken), "auraLpToken");
    vm.label(address(this), "test");

    adapter.initialize(abi.encode(asset, address(this), strategy, 0, sigs, ""), externalRegistry, testConfig);
  }

  /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

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
      string.concat("VaultCraft Aura ", IERC20Metadata(address(asset)).name(), " Adapter"),
      "name"
    );
    assertEq(
      IERC20Metadata(address(adapter)).symbol(),
      string.concat("vcAu-", IERC20Metadata(address(asset)).symbol()),
      "symbol"
    );

    assertEq(asset.allowance(address(adapter), address(auraBooster)), type(uint256).max, "allowance");
  }

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

    vm.warp(block.timestamp + 30 days);

    vm.prank(bob);

    adapter.withdraw(1, bob, bob);

    address[] memory rewardTokens = IWithRewards(address(adapter)).rewardTokens();
    assertEq(rewardTokens[0], 0xba100000625a3754423978a60c9317c58a424e3D); // BAL
    assertEq(rewardTokens[1], 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF); // AURA

    assertGt(IERC20(rewardTokens[0]).balanceOf(address(adapter)), 0);
    assertGt(IERC20(rewardTokens[1]).balanceOf(address(adapter)), 0);
  }
}
