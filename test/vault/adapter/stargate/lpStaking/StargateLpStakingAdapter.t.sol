// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { StargateLpStakingAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IStargateStaking } from "../../../../../src/vault/adapter/stargate/lpStaking/StargateLpStakingAdapter.sol";
import { StargateLpStakingTestConfigStorage, StargateLpStakingTestConfig } from "./StargateLpStakingTestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage, IAdapter } from "../../abstract/AbstractAdapterTest.sol";

contract StargateLpStakingAdapterTest is AbstractAdapterTest {
  using Math for uint256;

  IStargateStaking stargateStaking = IStargateStaking(0xB0D502E938ed5f4df2E681fE6E419ff29631d62b); //eth=0xB0D502E938ed5f4df2E681fE6E419ff29631d62b poly=0x8731d54E9D02c286767d56ac03e8037C07e01e98

  uint256 stakingPid;

  function setUp() public {
    uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
    vm.selectFork(forkId);

    testConfigStorage = ITestConfigStorage(address(new StargateLpStakingTestConfigStorage()));

    _setUpTest(testConfigStorage.getTestConfig(0));
  }

  function overrideSetup(bytes memory testConfig) public override {
    _setUpTest(testConfig);
  }

  function _setUpTest(bytes memory testConfig) internal {
    uint256 _stakingPid = abi.decode(testConfig, (uint256));

    (address _sToken, , , ) = stargateStaking.poolInfo(_stakingPid);

    stakingPid = _stakingPid;

    setUpBaseTest(
      IERC20(_sToken),
      address(new StargateLpStakingAdapter()),
      address(stargateStaking),
      10,
      "StargateLpStaking",
      true
    );

    vm.label(address(stargateStaking), "stargateStaking");
    vm.label(address(asset), "asset");
    vm.label(address(this), "test");

    adapter.initialize(abi.encode(asset, address(this), strategy, 0, sigs, ""), externalRegistry, testConfig);
  }

  /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

  function increasePricePerShare(uint256 amount) public override {
    //deal(address(asset), address(asset), asset.balanceOf(address(asset)) + amount);
  }

  function iouBalance() public view override returns (uint256) {
    (uint256 stake, ) = stargateStaking.userInfo(stakingPid, address(adapter));
    return stake;
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
    assertEq(
      IERC20Metadata(address(adapter)).name(),
      string.concat("VaultCraft Stargate LpStaking ", IERC20Metadata(address(asset)).name(), " Adapter"),
      "name"
    );
    assertEq(
      IERC20Metadata(address(adapter)).symbol(),
      string.concat("vcStgLpS-", IERC20Metadata(address(asset)).symbol()),
      "symbol"
    );

    assertEq(asset.allowance(address(adapter), address(stargateStaking)), type(uint256).max, "allowance");
  }
}
