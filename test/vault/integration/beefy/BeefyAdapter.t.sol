// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { BeefyAdapter, SafeERC20, IERC20, IERC20Metadata, IBeefyVault, IBeefyBooster, IBeefyStrat, IBeefyBalanceCheck, IWithRewards, IStrategy } from "../../../../src/vault/adapter/beefy/BeefyAdapter.sol";
import { BeefyTestConfigStorage, BeefyTestConfig } from "./BeefyTestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage, IAdapter, Math } from "../abstract/AbstractAdapterTest.sol";
import { IPermissionRegistry, Permission } from "../../../../src/interfaces/vault/IPermissionRegistry.sol";
import { PermissionRegistry } from "../../../../src/vault/PermissionRegistry.sol";
import { MockStrategyClaimer } from "../../../utils/mocks/MockStrategyClaimer.sol";

contract BeefyAdapterTest is AbstractAdapterTest {
  using Math for uint256;

  IBeefyBooster beefyBooster;
  IBeefyVault beefyVault;
  IBeefyBalanceCheck beefyBalanceCheck;
  IPermissionRegistry permissionRegistry;

  function setUp() public {
    testConfigStorage = ITestConfigStorage(address(new BeefyTestConfigStorage()));

    _setUpTest(testConfigStorage.getTestConfig(0));
  }

  function overrideSetup(bytes memory testConfig) public override {
    _setUpTest(testConfig);
  }

  function _setUpTest(bytes memory testConfig) internal {
    (address _beefyVault, address _beefyBooster, string memory _network) = abi.decode(
      testConfig,
      (address, address, string)
    );

    uint256 forkId = vm.createSelectFork(vm.rpcUrl(_network));
    vm.selectFork(forkId);

    beefyVault = IBeefyVault(_beefyVault);
    beefyBooster = IBeefyBooster(_beefyBooster);
    beefyBalanceCheck = IBeefyBalanceCheck(_beefyBooster == address(0) ? _beefyVault : _beefyBooster);

    // Endorse Beefy Vault
    permissionRegistry = IPermissionRegistry(address(new PermissionRegistry(address(this))));
    setPermission(_beefyVault, true, false);
    if (_beefyBooster != address(0)) {
      // Endorse Beefy Booster
      setPermission(_beefyBooster, true, false);
    }

    setUpBaseTest(
      IERC20(IBeefyVault(beefyVault).want()),
      address(new BeefyAdapter()),
      address(permissionRegistry),
      10,
      "Beefy ",
      true
    );

    vm.label(_beefyVault, "beefyVault");
    vm.label(_beefyBooster, "beefyBooster");
    vm.label(address(asset), "asset");
    vm.label(address(this), "test");

    adapter.initialize(abi.encode(asset, address(this), strategy, 0, sigs, ""), externalRegistry, testConfig);
  }

  /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

  function increasePricePerShare(uint256 amount) public override {
    deal(address(asset), address(beefyVault), asset.balanceOf(address(beefyVault)) + amount);
    beefyVault.earn();
  }

  function iouBalance() public view override returns (uint256) {
    return beefyBalanceCheck.balanceOf(address(adapter));
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
    assertEq(
      adapter.totalAssets(),
      iouBalance().mulDiv(beefyVault.balance(), beefyVault.totalSupply(), Math.Rounding.Down),
      string.concat("totalAssets != beefy assets", baseTestId)
    );
  }

  function setPermission(address target, bool endorsed, bool rejected) public {
    address[] memory targets = new address[](1);
    Permission[] memory permissions = new Permission[](1);
    targets[0] = target;
    permissions[0] = Permission(endorsed, rejected);
    permissionRegistry.setPermissions(targets, permissions);
  }

  /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

  function test__initialization() public override {
    testConfigStorage = ITestConfigStorage(address(new BeefyTestConfigStorage()));

    (address _beefyVault, address _beefyBooster, string memory _network) = abi.decode(
      testConfigStorage.getTestConfig(0),
      (address, address, string)
    );

    createAdapter();
    uint256 callTime = block.timestamp;

    if (address(strategy) != address(0)) {
      vm.expectEmit(false, false, false, true, address(strategy));
      emit SelectorsVerified();
      vm.expectEmit(false, false, false, true, address(strategy));
      emit AdapterVerified();
      vm.expectEmit(false, false, false, true, address(strategy));
      emit StrategySetup();
    }
    vm.expectEmit(false, false, false, true, address(adapter));
    emit Initialized(uint8(1));
    adapter.initialize(
      abi.encode(asset, address(this), strategy, 0, sigs, ""),
      externalRegistry,
      abi.encode(_beefyVault, _beefyBooster)
    );

    assertEq(adapter.owner(), address(this), "owner");
    assertEq(adapter.strategy(), address(strategy), "strategy");
    assertEq(adapter.harvestCooldown(), 0, "harvestCooldown");
    assertEq(adapter.strategyConfig(), "", "strategyConfig");
    assertEq(
      IERC20Metadata(address(adapter)).decimals(),
      IERC20Metadata(address(asset)).decimals() + adapter.decimalOffset(),
      "decimals"
    );

    verify_adapterInit();
  }

  function verify_adapterInit() public override {
    assertEq(adapter.asset(), beefyVault.want(), "asset");
    assertEq(
      IERC20Metadata(address(adapter)).name(),
      string.concat("VaultCraft Beefy ", IERC20Metadata(address(asset)).name(), " Adapter"),
      "name"
    );
    assertEq(
      IERC20Metadata(address(adapter)).symbol(),
      string.concat("vcB-", IERC20Metadata(address(asset)).symbol()),
      "symbol"
    );

    assertEq(asset.allowance(address(adapter), address(beefyVault)), type(uint256).max, "allowance");

    // Test Beefy Config Boundaries
    createAdapter();
    (address _beefyVault, address _beefyBooster) = abi.decode(testConfigStorage.getTestConfig(0), (address, address));
    setPermission(_beefyVault, false, false);
    if (_beefyBooster != address(0)) setPermission(_beefyBooster, true, false);

    vm.expectRevert(abi.encodeWithSelector(BeefyAdapter.NotEndorsed.selector, _beefyVault));
    adapter.initialize(
      abi.encode(asset, address(this), strategy, 0, sigs, ""),
      address(permissionRegistry),
      abi.encode(_beefyVault, _beefyBooster)
    );

    setPermission(_beefyVault, true, false);
    setPermission(address(0x3af3563Ba5C68EB7DCbAdd2dF0FcE4CC9818e75c), true, false);

    // Using Retired USD+-MATIC vLP vault on polygon
    vm.expectRevert(
      abi.encodeWithSelector(
        BeefyAdapter.InvalidBeefyVault.selector,
        address(0x3af3563Ba5C68EB7DCbAdd2dF0FcE4CC9818e75c)
      )
    );
    adapter.initialize(
      abi.encode(asset, address(this), strategy, 0, sigs, ""),
      address(permissionRegistry),
      abi.encode(address(0x3af3563Ba5C68EB7DCbAdd2dF0FcE4CC9818e75c), _beefyBooster)
    );

    // Using stMATIC-MATIC vault Booster on polygon
    setPermission(0xBb77dDe3101B8f9B71755ABe2F69b64e79AE4A41, true, false);
    vm.expectRevert(
      abi.encodeWithSelector(
        BeefyAdapter.InvalidBeefyBooster.selector,
        address(0xBb77dDe3101B8f9B71755ABe2F69b64e79AE4A41)
      )
    );
    adapter.initialize(
      abi.encode(asset, address(this), strategy, 0, sigs, ""),
      address(permissionRegistry),
      abi.encode(_beefyVault, address(0xBb77dDe3101B8f9B71755ABe2F69b64e79AE4A41))
    );
  }

  /*//////////////////////////////////////////////////////////////
                    DEPOSIT/MINT/WITHDRAW/REDEEM
    //////////////////////////////////////////////////////////////*/

  function test__deposit(uint8 fuzzAmount) public override {
    testConfigStorage = ITestConfigStorage(address(new BeefyTestConfigStorage()));

    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);
    uint8 len = uint8(testConfigStorage.getTestConfigLength());
    for (uint8 i; i < len; i++) {
      if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

      _mintAssetAndApproveForAdapter(amount, bob);
      prop_deposit(bob, bob, amount, testId);

      increasePricePerShare(raise);

      _mintAssetAndApproveForAdapter(amount, bob);
      prop_deposit(bob, alice, amount, testId);
    }
  }

  function test__mint(uint8 fuzzAmount) public override {
    testConfigStorage = ITestConfigStorage(address(new BeefyTestConfigStorage()));

    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);
    uint8 len = uint8(testConfigStorage.getTestConfigLength());
    for (uint8 i; i < len; i++) {
      if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

      _mintAssetAndApproveForAdapter(adapter.previewMint(amount), bob);
      prop_mint(bob, bob, amount, testId);

      increasePricePerShare(raise);

      _mintAssetAndApproveForAdapter(adapter.previewMint(amount), bob);
      prop_mint(bob, alice, amount, testId);
    }
  }

  function test__withdraw(uint8 fuzzAmount) public override {
    testConfigStorage = ITestConfigStorage(address(new BeefyTestConfigStorage()));

    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);
    uint8 len = uint8(testConfigStorage.getTestConfigLength());
    for (uint8 i; i < len; i++) {
      if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

      uint256 reqAssets = (adapter.previewMint(adapter.previewWithdraw(amount)) * 10) / 8;
      _mintAssetAndApproveForAdapter(reqAssets, bob);
      vm.prank(bob);
      adapter.deposit(reqAssets, bob);
      prop_withdraw(bob, bob, amount, testId);

      _mintAssetAndApproveForAdapter(reqAssets, bob);
      vm.prank(bob);
      adapter.deposit(reqAssets, bob);

      increasePricePerShare(raise);

      vm.prank(bob);
      adapter.approve(alice, type(uint256).max);
      prop_withdraw(alice, bob, amount, testId);
    }
  }

  function test__redeem(uint8 fuzzAmount) public override {
    testConfigStorage = ITestConfigStorage(address(new BeefyTestConfigStorage()));

    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);
    uint8 len = uint8(testConfigStorage.getTestConfigLength());
    for (uint8 i; i < len; i++) {
      if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

      uint256 reqAssets = (adapter.previewMint(amount) * 10) / 9;
      _mintAssetAndApproveForAdapter(reqAssets, bob);
      vm.prank(bob);
      adapter.deposit(reqAssets, bob);
      prop_redeem(bob, bob, amount, testId);

      _mintAssetAndApproveForAdapter(reqAssets, bob);
      vm.prank(bob);
      adapter.deposit(reqAssets, bob);

      increasePricePerShare(raise);

      vm.prank(bob);
      adapter.approve(alice, type(uint256).max);
      prop_redeem(alice, bob, amount, testId);
    }
  }

  /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
    //////////////////////////////////////////////////////////////*/

  // NOTE - The beefy adapter suffers often from an off-by-one error which "steals" 1 wei from the user
  function test__RT_deposit_withdraw() public override {
    _mintAssetAndApproveForAdapter(defaultAmount, bob);

    vm.startPrank(bob);
    uint256 shares1 = adapter.deposit(defaultAmount, bob);
    uint256 shares2 = adapter.withdraw(defaultAmount - 1, bob, bob);
    vm.stopPrank();

    assertGe(shares2, shares1, testId);
  }

  // NOTE - The beefy adapter suffers often from an off-by-one error which "steals" 1 wei from the user
  function test__RT_mint_withdraw() public override {
    _mintAssetAndApproveForAdapter(adapter.previewMint(defaultAmount), bob);

    vm.startPrank(bob);
    uint256 assets = adapter.mint(defaultAmount, bob);
    uint256 shares = adapter.withdraw(assets - 1, bob, bob);
    vm.stopPrank();

    assertGe(shares, defaultAmount, testId);
  }

  /*//////////////////////////////////////////////////////////////
                              PAUSE
    //////////////////////////////////////////////////////////////*/

  function test__unpause() public override {
    _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);

    vm.prank(bob);
    adapter.deposit(defaultAmount, bob);

    uint256 oldTotalAssets = adapter.totalAssets();
    uint256 oldTotalSupply = adapter.totalSupply();
    uint256 oldIouBalance = iouBalance();

    adapter.pause();
    adapter.unpause();

    // We simply deposit back into the external protocol
    // TotalSupply and Assets dont change
    // @dev overriden _delta_
    assertApproxEqAbs(oldTotalAssets, adapter.totalAssets(), 50, "totalAssets");
    assertApproxEqAbs(oldTotalSupply, adapter.totalSupply(), 50, "totalSupply");
    assertApproxEqAbs(asset.balanceOf(address(adapter)), 0, 50, "asset balance");
    assertApproxEqRel(iouBalance(), oldIouBalance, 1, "iou balance");

    // Deposit and mint dont revert
    vm.startPrank(bob);
    adapter.deposit(defaultAmount, bob);
    adapter.mint(defaultAmount, bob);
  }

  /*//////////////////////////////////////////////////////////////
                              CLAIM
    //////////////////////////////////////////////////////////////*/

  function test__claim() public override {
    testConfigStorage = ITestConfigStorage(address(new BeefyTestConfigStorage()));
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

    vm.warp(block.timestamp + 10 days);

    vm.prank(bob);
    adapter.withdraw(1, bob, bob);

    address[] memory rewardTokens = IWithRewards(address(adapter)).rewardTokens();
    assertEq(rewardTokens[0], beefyBooster.rewardToken());

    assertGt(IERC20(rewardTokens[0]).balanceOf(address(adapter)), 0);
  }
}
