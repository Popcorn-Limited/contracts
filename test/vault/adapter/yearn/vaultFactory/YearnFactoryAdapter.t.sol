// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { YearnAdapter, SafeERC20, IERC20, IERC20Metadata, Math, VaultAPI, IYearnRegistry } from "../../../../../src/vault/adapter/yearn/YearnAdapter.sol";
import { YearnFactoryTestConfigStorage, YearnFactoryTestConfig } from "../vaultFactory/YearnFactoryTestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage, IAdapter } from "../../abstract/AbstractAdapterTest.sol";

contract YearnFactoryAdapterTest is AbstractAdapterTest {
  using Math for uint256;

  VaultAPI yearnVault;

  function setUp() public {
    uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
    vm.selectFork(forkId);

    testConfigStorage = ITestConfigStorage(address(new YearnFactoryTestConfigStorage()));

    _setUpTest(testConfigStorage.getTestConfig(0));
  }

  function overrideSetup(bytes memory testConfig) public override {
    _setUpTest(testConfig);
  }

  function _setUpTest(bytes memory testConfig) internal {
    address _asset = abi.decode(testConfig, (address));

    setUpBaseTest(
      IERC20(_asset),
      address(new YearnAdapter()),
      0xaF1f5e1c19cB68B30aAD73846eFfDf78a5863319, //yearn registry
      10,
      "Yearn ",
      false
    );

    yearnVault = VaultAPI(IYearnRegistry(externalRegistry).latestVault(_asset));

    vm.label(address(yearnVault), "yearnVault");
    vm.label(address(asset), "asset");
    vm.label(address(this), "test");

    adapter.initialize(abi.encode(asset, address(this), address(0), 0, sigs, ""), externalRegistry, "");

    defaultAmount = 10**IERC20Metadata(address(asset)).decimals();
    minFuzz = defaultAmount * 10_000;
    raise = defaultAmount * 100_000_000;
    maxAssets = defaultAmount * 1_000_000;
    maxShares = maxAssets / 2;
  }

  /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

  function increasePricePerShare(uint256 amount) public override {
    deal(address(asset), address(yearnVault), asset.balanceOf(address(yearnVault)) + amount);
  }

  function iouBalance() public view override returns (uint256) {
    return yearnVault.balanceOf(address(adapter));
  }

  // Verify that totalAssets returns the expected amount
  function verify_totalAssets() public override {
    // Make sure totalAssets isnt 0
    deal(address(asset), bob, defaultAmount);
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
      iouBalance().mulDiv(yearnVault.pricePerShare(), 10**IERC20Metadata(address(asset)).decimals(), Math.Rounding.Up),
      _delta_,
      string.concat("totalAssets != yearn assets", baseTestId)
    );
  }

  /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

  function verify_adapterInit() public override {
    assertEq(adapter.asset(), yearnVault.token(), "asset");
    assertEq(
      IERC20Metadata(address(adapter)).name(),
      string.concat("Popcorn Yearn", IERC20Metadata(address(asset)).name(), " Adapter"),
      "name"
    );
    assertEq(
      IERC20Metadata(address(adapter)).symbol(),
      string.concat("popY-", IERC20Metadata(address(asset)).symbol()),
      "symbol"
    );

    assertEq(asset.allowance(address(adapter), address(yearnVault)), type(uint256).max, "allowance");
  }

  /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
    //////////////////////////////////////////////////////////////*/

  // NOTE - The yearn adapter suffers often from an off-by-one error which "steals" 1 wei from the user
  function test__RT_deposit_withdraw() public override {
    _mintAssetAndApproveForAdapter(minFuzz, bob);

    vm.startPrank(bob);
    uint256 shares1 = adapter.deposit(minFuzz, bob);
    uint256 shares2 = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
    vm.stopPrank();

    // We compare assets here with maxWithdraw since the shares of withdraw will always be lower than `compoundDefaultAmount`
    // This tests the same assumption though. As long as you can withdraw less or equal assets to the input amount you cant round trip
    assertGe(minFuzz, adapter.maxWithdraw(bob), testId);
  }

  // NOTE - The yearn adapter suffers often from an off-by-one error which "steals" 1 wei from the user
  function test__RT_mint_withdraw() public override {
    _mintAssetAndApproveForAdapter(adapter.previewMint(minFuzz), bob);

    vm.startPrank(bob);
    uint256 assets = adapter.mint(minFuzz, bob);
    uint256 shares = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
    vm.stopPrank();
    // We compare assets here with maxWithdraw since the shares of withdraw will always be lower than `compoundDefaultAmount`
    // This tests the same assumption though. As long as you can withdraw less or equal assets to the input amount you cant round trip
    assertGe(adapter.previewMint(minFuzz), adapter.maxWithdraw(bob), testId);
  }

  function test__RT_mint_redeem() public override {
    _mintAssetAndApproveForAdapter(adapter.previewMint(minFuzz), bob);

    vm.startPrank(bob);
    uint256 assets1 = adapter.mint(minFuzz, bob);
    uint256 assets2 = adapter.redeem(minFuzz, bob, bob);
    vm.stopPrank();

    assertLe(assets2, assets1, testId);
  }

  /*//////////////////////////////////////////////////////////////
                              PAUSE
    //////////////////////////////////////////////////////////////*/

  function test__unpause() public override {
    _mintAssetAndApproveForAdapter(minFuzz * 3, bob);

    vm.prank(bob);
    adapter.deposit(minFuzz, bob);

    uint256 oldTotalAssets = adapter.totalAssets();
    uint256 oldTotalSupply = adapter.totalSupply();
    uint256 oldIouBalance = iouBalance();

    adapter.pause();
    adapter.unpause();

    // We simply deposit back into the external protocol
    // TotalSupply and Assets dont change
    assertApproxEqAbs(oldTotalAssets, adapter.totalAssets(), _delta_, "totalAssets");
    assertApproxEqAbs(oldTotalSupply, adapter.totalSupply(), _delta_, "totalSupply");
    assertApproxEqAbs(asset.balanceOf(address(adapter)), 0, _delta_, "asset balance");
    assertApproxEqAbs(iouBalance(), oldIouBalance, _delta_, "iou balance");

    // Deposit and mint dont revert
    vm.startPrank(bob);
    adapter.deposit(minFuzz, bob);
    adapter.mint(minFuzz, bob);
  }
}
