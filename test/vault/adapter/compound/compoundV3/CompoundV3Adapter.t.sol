// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { CompoundV3Adapter, SafeERC20, IERC20, IERC20Metadata, Math, ICToken, ICometRewarder, IGovernor, IAdmin, ICometConfigurator } from "../../../../../src/vault/adapter/compound/compoundV3/CompoundV3Adapter.sol";
import { CompoundV3TestConfigStorage, CompoundV3TestConfig } from "./CompoundV3TestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage, IAdapter } from "../../abstract/AbstractAdapterTest.sol";

contract CompoundV3AdapterTest is AbstractAdapterTest {
  using Math for uint256;

  ICToken cToken;
  ICometRewarder cometRewarder;
  ICometConfigurator cometConfigurator = ICometConfigurator(0x316f9708bB98af7dA9c68C1C3b5e79039cD336E3);

  uint256 compoundDefaultAmount = 1e18;

  function setUp() public {
    uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
    vm.selectFork(forkId);

    testConfigStorage = ITestConfigStorage(address(new CompoundV3TestConfigStorage()));

    _setUpTest(testConfigStorage.getTestConfig(0));
  }

  function overrideSetup(bytes memory testConfig) public override {
    _setUpTest(testConfig);
  }

  function _setUpTest(bytes memory testConfig) internal {
    (address _cToken, address _cometRewarder) = abi.decode(testConfig, (address, address));

    cToken = ICToken(_cToken);
    cometRewarder = ICometRewarder(_cometRewarder);

    asset = IERC20(cToken.baseToken());

    address configuratorBaseToken = cometConfigurator.getConfiguration(address(cToken)).baseToken;
    assertEq(address(asset), configuratorBaseToken, "InvalidAsset");

    setUpBaseTest(IERC20(asset), address(new CompoundV3Adapter()), address(cometConfigurator), 10, "CompoundV3", true);

    vm.label(address(cToken), "cToken");
    vm.label(address(cometRewarder), "cometRewarder");
    vm.label(address(asset), "asset");
    vm.label(address(this), "test");

    adapter.initialize(abi.encode(asset, address(this), strategy, 0, sigs, ""), externalRegistry, testConfig);
  }

  /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

  function increasePricePerShare(uint256 amount) public override {
    deal(address(asset), address(cToken), asset.balanceOf(address(cToken)) + amount);
  }

  function iouBalance() public view override returns (uint256) {
    return cToken.balanceOf(address(adapter));
  }

  // Verify that totalAssets returns the expected amount
  function verify_totalAssets() public override {
    // Make sure totalAssets isn't 0
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
    assertEq(adapter.asset(), cToken.baseToken(), "asset");
    assertEq(
      IERC20Metadata(address(adapter)).name(),
      string.concat("VaultCraft CompoundV3 ", IERC20Metadata(address(asset)).name(), " Adapter"),
      "name"
    );
    assertEq(
      IERC20Metadata(address(adapter)).symbol(),
      string.concat("vcCv3-", IERC20Metadata(address(asset)).symbol()),
      "symbol"
    );

    assertEq(asset.allowance(address(adapter), address(cToken)), type(uint256).max, "allowance");
  }

  /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
    //////////////////////////////////////////////////////////////*/

  function test__RT_deposit_withdraw() public override {
    _mintAssetAndApproveForAdapter(compoundDefaultAmount, bob);

    vm.startPrank(bob);
    uint256 shares1 = adapter.deposit(compoundDefaultAmount, bob);
    uint256 shares2 = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
    vm.stopPrank();

    // We compare assets here with maxWithdraw since the shares of withdraw will always be lower than `compoundDefaultAmount`
    // This tests the same assumption though. As long as you can withdraw less or equal assets to the input amount you cant round trip
    assertGe(compoundDefaultAmount, adapter.maxWithdraw(bob), testId);
  }

  function test__RT_mint_withdraw() public override {
    _mintAssetAndApproveForAdapter(adapter.previewMint(compoundDefaultAmount), bob);

    vm.startPrank(bob);
    uint256 assets = adapter.mint(compoundDefaultAmount, bob);
    uint256 shares = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
    vm.stopPrank();
    // We compare assets here with maxWithdraw since the shares of withdraw will always be lower than `compoundDefaultAmount`
    // This tests the same assumption though. As long as you can withdraw less or equal assets to the input amount you cant round trip
    assertGe(assets, adapter.maxWithdraw(bob), testId);
  }

  /*//////////////////////////////////////////////////////////////
                              PAUSE
    //////////////////////////////////////////////////////////////*/

  function test__unpause() public override {
    _mintAssetAndApproveForAdapter(3e18, bob);

    vm.prank(bob);
    adapter.deposit(1e18, bob);

    uint256 oldTotalAssets = adapter.totalAssets();
    uint256 oldTotalSupply = adapter.totalSupply();
    uint256 oldIouBalance = iouBalance();

    adapter.pause();
    adapter.unpause();

    // We simply deposit back into the external protocol
    // TotalSupply and Assets dont change
    // A Tiny change in cToken balance will throw of the assets by some margin.
    assertApproxEqAbs(oldTotalAssets, adapter.totalAssets(), 3e8, "totalAssets");
    assertApproxEqAbs(oldTotalSupply, adapter.totalSupply(), _delta_, "totalSupply");
    assertApproxEqAbs(asset.balanceOf(address(adapter)), 0, _delta_, "asset balance");
    assertApproxEqAbs(iouBalance(), oldIouBalance, _delta_, "iou balance");

    // Deposit and mint dont revert
    vm.startPrank(bob);
    adapter.deposit(1e18, bob);
    adapter.mint(1e18, bob);
  }

  function test__harvest() public override {
    uint256 performanceFee = 1e16;
    uint256 hwm = 1e9;
    _mintAssetAndApproveForAdapter(defaultAmount, bob);

    vm.prank(bob);
    adapter.deposit(defaultAmount, bob);

    uint256 oldTotalAssets = adapter.totalAssets();
    adapter.setPerformanceFee(performanceFee);
    emit log_named_uint("aBal1", asset.balanceOf(address(cToken)));

    increasePricePerShare(raise);

    // We need to advance time so compound can accrue the interest
    vm.warp(block.timestamp + 100);

    uint256 gain = ((adapter.convertToAssets(1e18) - adapter.highWaterMark()) * adapter.totalSupply()) / 1e18;
    uint256 fee = (gain * performanceFee) / 1e18;
    uint256 expectedFee = adapter.convertToShares(fee);

    vm.expectEmit(false, false, false, true, address(adapter));
    emit Harvested();

    adapter.harvest();

    // Multiply with the decimal offset
    assertApproxEqAbs(adapter.totalSupply(), defaultAmount * 1e9 + expectedFee, _delta_, "totalSupply");
    assertApproxEqAbs(adapter.balanceOf(feeRecipient), expectedFee, _delta_, "expectedFee");
  }
}
