// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { CompoundV2Adapter, SafeERC20, IERC20, IERC20Metadata, Math, ICToken, IComptroller } from "../../../../../src/vault/adapter/compound/compoundV2/CompoundV2Adapter.sol";
import { FluxTestConfigStorage, FluxTestConfig } from "./FluxTestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage, IAdapter } from "../../abstract/AbstractAdapterTest.sol";

contract FluxAdapterTest is AbstractAdapterTest {
  using Math for uint256;

  ICToken fToken;
  IComptroller comptroller;

  uint256 fluxDefaultAmount = 1e18;

  function setUp() public {
    uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
    vm.selectFork(forkId);

    testConfigStorage = ITestConfigStorage(address(new FluxTestConfigStorage()));

    _setUpTest(testConfigStorage.getTestConfig(0));
  }

  function overrideSetup(bytes memory testConfig) public override {
    _setUpTest(testConfig);
  }

  function _setUpTest(bytes memory testConfig) internal {
    address _fToken = abi.decode(testConfig, (address));

    fToken = ICToken(_fToken);
    asset = IERC20(fToken.underlying());
    comptroller = IComptroller(fToken.comptroller());

    (bool isListed, , ) = comptroller.markets(address(fToken));
    assertEq(isListed, true, "InvalidAsset");

    setUpBaseTest(IERC20(asset), address(new CompoundV2Adapter()), address(comptroller), 10, "CompoundV2", true);

    vm.label(address(fToken), "fToken");
    vm.label(address(comptroller), "comptroller");
    vm.label(address(asset), "asset");
    vm.label(address(this), "test");

    adapter.initialize(abi.encode(asset, address(this), strategy, 0, sigs, ""), externalRegistry, testConfig);
  }

  /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

  function increasePricePerShare(uint256 amount) public override {
    deal(address(asset), address(fToken), asset.balanceOf(address(fToken)) + amount);
  }

  function iouBalance() public view override returns (uint256) {
    return fToken.balanceOf(address(adapter));
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
    assertEq(adapter.asset(), fToken.underlying(), "asset");
    assertEq(
      IERC20Metadata(address(adapter)).name(),
      string.concat("VaultCraft CompoundV2 ", IERC20Metadata(address(asset)).name(), " Adapter"),
      "name"
    );
    assertEq(
      IERC20Metadata(address(adapter)).symbol(),
      string.concat("vcCv2-", IERC20Metadata(address(asset)).symbol()),
      "symbol"
    );

    assertEq(asset.allowance(address(adapter), address(fToken)), type(uint256).max, "allowance");
  }

  /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
    //////////////////////////////////////////////////////////////*/

  function test__RT_deposit_withdraw() public override {
    _mintAssetAndApproveForAdapter(fluxDefaultAmount, bob);

    vm.startPrank(bob);
    uint256 shares1 = adapter.deposit(fluxDefaultAmount, bob);
    uint256 shares2 = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
    vm.stopPrank();

    // We compare assets here with maxWithdraw since the shares of withdraw will always be lower than `fluxDefaultAmount`
    // This tests the same assumption though. As long as you can withdraw less or equal assets to the input amount you cant round trip
    assertGe(fluxDefaultAmount, adapter.maxWithdraw(bob), testId);
  }

  function test__RT_mint_withdraw() public override {
    _mintAssetAndApproveForAdapter(adapter.previewMint(fluxDefaultAmount), bob);

    vm.startPrank(bob);
    uint256 assets = adapter.mint(fluxDefaultAmount, bob);
    uint256 shares = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
    vm.stopPrank();
    // We compare assets here with maxWithdraw since the shares of withdraw will always be lower than `fluxDefaultAmount`
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
}
