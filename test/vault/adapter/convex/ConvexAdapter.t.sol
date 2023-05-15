// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { ConvexAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IConvexBooster, IConvexRewards, IWithRewards, IStrategy } from "../../../../src/vault/adapter/convex/ConvexAdapter.sol";
import { ConvexTestConfigStorage, ConvexTestConfig } from "./ConvexTestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage, IAdapter } from "../abstract/AbstractAdapterTest.sol";
import { MockStrategyClaimer } from "../../../utils/mocks/MockStrategyClaimer.sol";

contract ConvexAdapterTest is AbstractAdapterTest {
  using Math for uint256;

  IConvexBooster convexBooster = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
  IConvexRewards convexRewards;
  uint256 pid;

  function setUp() public {
    uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
    vm.selectFork(forkId);

    testConfigStorage = ITestConfigStorage(address(new ConvexTestConfigStorage()));

    _setUpTest(testConfigStorage.getTestConfig(0));
  }

  function overrideSetup(bytes memory testConfig) public override {
    _setUpTest(testConfig);
  }

  function _setUpTest(bytes memory testConfig) internal {
    uint256 _pid = abi.decode(testConfig, (uint256));

    pid = _pid;

    (address _asset, , , address _convexRewards, , ) = convexBooster.poolInfo(pid);
    convexRewards = IConvexRewards(_convexRewards);

    setUpBaseTest(IERC20(_asset), address(new ConvexAdapter()), address(convexBooster), 10, "Convex", true);

    vm.label(address(convexBooster), "convexBooster");
    vm.label(address(convexRewards), "convexRewards");
    vm.label(address(asset), "asset");
    vm.label(address(this), "test");

    adapter.initialize(abi.encode(asset, address(this), strategy, 0, sigs, ""), externalRegistry, testConfig);
  }

  /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

  function increasePricePerShare(uint256 amount) public override {
    deal(address(asset), address(convexRewards), asset.balanceOf(address(convexRewards)) + amount);
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
    assertEq(adapter.asset(), address(asset), "asset");
    assertEq(
      IERC20Metadata(address(adapter)).name(),
      string.concat("VaultCraft Convex ", IERC20Metadata(address(asset)).name(), " Adapter"),
      "name"
    );
    assertEq(
      IERC20Metadata(address(adapter)).symbol(),
      string.concat("vcCvx-", IERC20Metadata(address(asset)).symbol()),
      "symbol"
    );

    assertEq(asset.allowance(address(adapter), address(convexBooster)), type(uint256).max, "allowance");
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

    vm.warp(block.timestamp + 30 days);

    vm.prank(bob);
    adapter.withdraw(1, bob, bob);

    address[] memory rewardTokens = IWithRewards(address(adapter)).rewardTokens();
    assertEq(rewardTokens[0], 0xD533a949740bb3306d119CC777fa900bA034cd52); // CRV
    assertEq(rewardTokens[1], 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B); // CVX

    assertGt(IERC20(rewardTokens[0]).balanceOf(address(adapter)), 0);
    assertGt(IERC20(rewardTokens[1]).balanceOf(address(adapter)), 0);
  }
}
