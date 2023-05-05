// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { PropertyTest } from "./PropertyTest.prop.sol";
import { IAdapter, IERC4626 } from "../../../../src/interfaces/vault/IAdapter.sol";
import { IStrategy } from "../../../../src/interfaces/vault/IStrategy.sol";
import { IERC20Upgradeable as IERC20, IERC20MetadataUpgradeable as IERC20Metadata } from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { ITestConfigStorage } from "./ITestConfigStorage.sol";
import { MockStrategy } from "../../../utils/mocks/MockStrategy.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";

contract AbstractAdapterTest is PropertyTest {
  using Math for uint256;

  ITestConfigStorage testConfigStorage;

  string baseTestId; // Depends on external Protocol (e.g. Beefy,Yearn...)
  string testId; // baseTestId + Asset

  bytes32 constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

  address bob = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
  address alice = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
  address feeRecipient = address(0x4444);

  uint256 defaultAmount;
  uint256 raise;

  uint256 minFuzz = 1e10;
  uint256 maxAssets;
  uint256 maxShares;

  IERC20 asset;
  address implementation;
  IAdapter adapter;
  IStrategy strategy;
  address externalRegistry;

  bytes4[8] sigs;

  error MaxError(uint256 amount);

  function setUpBaseTest(
    IERC20 asset_,
    address implementation_,
    address externalRegistry_,
    uint256 delta_,
    string memory baseTestId_,
    bool useStrategy_
  ) public {
    asset = asset_;

    implementation = implementation_;
    adapter = IAdapter(Clones.clone(implementation_));
    externalRegistry = externalRegistry_;

    // Setup PropertyTest
    _vault_ = address(adapter);
    _asset_ = address(asset_);
    _delta_ = delta_;

    defaultAmount = 10 ** IERC20Metadata(address(asset_)).decimals() * 1e9;

    raise = defaultAmount;
    maxAssets = defaultAmount * 1000;
    maxShares = maxAssets / 2;

    baseTestId = baseTestId_;
    testId = string.concat(baseTestId_, IERC20Metadata(address(asset)).symbol());

    if (useStrategy_) strategy = IStrategy(address(new MockStrategy()));
  }

  /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

  // NOTE: You MUST override these

  // Its should use exactly setup to override the previous setup
  function overrideSetup(bytes memory testConfig) public virtual {
    // setUpBasetest();
    // protocol specific setup();
  }

  // Clone a new Adapter and set it to `adapter`
  function createAdapter() public {
    adapter = IAdapter(Clones.clone(implementation));
    vm.label(address(adapter), "adapter");
  }

  // Increase the pricePerShare of the external protocol
  // sometimes its enough to simply add assets, othertimes one also needs to call some functions before the external protocol reflects the change
  function increasePricePerShare(uint256 amount) public virtual {}

  // Check the balance of the external protocol held by the adapter
  // Most of the time this should be a simple `balanceOf` call to the external protocol but some might have different implementations
  function iouBalance() public view virtual returns (uint256) {
    // extProt.balanceOf(address(adapter))
  }

  // Verify that totalAssets returns the expected amount
  function verify_totalAssets() public virtual {}

  function verify_adapterInit() public virtual {}

  function _mintAsset(uint256 amount, address receiver) internal virtual {
    deal(address(asset), receiver, amount);
  }

  function _mintAssetAndApproveForAdapter(uint256 amount, address receiver) internal {
    _mintAsset(amount, receiver);
    vm.prank(receiver);
    asset.approve(address(adapter), amount);
  }

  /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

  event SelectorsVerified();
  event AdapterVerified();
  event StrategySetup();
  event Initialized(uint8 version);

  function test__initialization() public virtual {
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
      testConfigStorage.getTestConfig(0)
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

  /*//////////////////////////////////////////////////////////////
                          GENERAL VIEWS
    //////////////////////////////////////////////////////////////*/

  // OPTIONAL
  function test__rewardsTokens() public virtual {}

  function test__asset() public virtual {
    prop_asset();
  }

  function test__totalAssets() public virtual {
    prop_totalAssets();
    verify_totalAssets();
  }

  /*//////////////////////////////////////////////////////////////
                          CONVERSION VIEWS
    //////////////////////////////////////////////////////////////*/

  function test__convertToShares() public virtual {
    prop_convertToShares(bob, alice, defaultAmount);
  }

  function test__convertToAssets() public virtual {
    prop_convertToAssets(bob, alice, defaultAmount);
  }

  /*//////////////////////////////////////////////////////////////
                          MAX VIEWS
    //////////////////////////////////////////////////////////////*/

  // NOTE: These Are just prop tests currently. Override tests here if the adapter has unique max-functions which override AdapterBase.sol

  function test__maxDeposit() public virtual {
    prop_maxDeposit(bob);

    // Deposit smth so withdraw on pause is not 0
    _mintAsset(defaultAmount, address(this));
    asset.approve(address(adapter), defaultAmount);
    adapter.deposit(defaultAmount, address(this));

    adapter.pause();
    assertEq(adapter.maxDeposit(bob), 0);
  }

  function test__maxMint() public virtual {
    prop_maxMint(bob);

    // Deposit smth so withdraw on pause is not 0
    _mintAsset(defaultAmount, address(this));
    asset.approve(address(adapter), defaultAmount);
    adapter.deposit(defaultAmount, address(this));

    adapter.pause();
    assertEq(adapter.maxMint(bob), 0);
  }

  function test__maxWithdraw() public virtual {
    prop_maxWithdraw(bob);
  }

  function test__maxRedeem() public virtual {
    prop_maxRedeem(bob);
  }

  /*//////////////////////////////////////////////////////////////
                          PREVIEW VIEWS
    //////////////////////////////////////////////////////////////*/
  function test__previewDeposit(uint8 fuzzAmount) public virtual {
    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

    _mintAsset(maxAssets, bob);
    vm.prank(bob);
    asset.approve(address(adapter), maxAssets);

    prop_previewDeposit(bob, bob, amount, testId);
  }

  function test__previewMint(uint8 fuzzAmount) public virtual {
    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);

    _mintAsset(maxAssets, bob);
    vm.prank(bob);
    asset.approve(address(adapter), maxAssets);

    prop_previewMint(bob, bob, amount, testId);
  }

  function test__previewWithdraw(uint8 fuzzAmount) public virtual {
    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

    uint256 reqAssets = adapter.previewMint(adapter.previewWithdraw(amount)) * 10;
    _mintAssetAndApproveForAdapter(reqAssets, bob);
    vm.prank(bob);
    adapter.deposit(reqAssets, bob);

    prop_previewWithdraw(bob, bob, bob, amount, testId);
  }

  function test__previewRedeem(uint8 fuzzAmount) public virtual {
    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);

    uint256 reqAssets = adapter.previewMint(amount) * 10;
    _mintAssetAndApproveForAdapter(reqAssets, bob);
    vm.prank(bob);
    adapter.deposit(reqAssets, bob);

    prop_previewRedeem(bob, bob, bob, amount, testId);
  }

  /*//////////////////////////////////////////////////////////////
                    DEPOSIT/MINT/WITHDRAW/REDEEM
    //////////////////////////////////////////////////////////////*/

  function test__deposit(uint8 fuzzAmount) public virtual {
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

  function test__mint(uint8 fuzzAmount) public virtual {
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

  function test__withdraw(uint8 fuzzAmount) public virtual {
    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);
    
    uint8 len = uint8(testConfigStorage.getTestConfigLength());
    for (uint8 i; i < len; i++) {
      if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

      uint256 reqAssets = adapter.previewMint(adapter.previewWithdraw(amount)) * 10;
      _mintAssetAndApproveForAdapter(reqAssets, bob);
      vm.prank(bob);
      adapter.deposit(reqAssets, bob);

      prop_withdraw(bob, bob, amount / 10, testId);

      _mintAssetAndApproveForAdapter(reqAssets, bob);
      vm.prank(bob);
      adapter.deposit(reqAssets, bob);

      increasePricePerShare(raise);

      vm.prank(bob);
      adapter.approve(alice, type(uint256).max);

      prop_withdraw(alice, bob, amount, testId);
    }
  }

  function test__redeem(uint8 fuzzAmount) public virtual {
    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);
    uint8 len = uint8(testConfigStorage.getTestConfigLength());
    for (uint8 i; i < len; i++) {
      if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

      uint256 reqAssets = adapter.previewMint(amount) * 10;
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

  function test__RT_deposit_redeem() public virtual {
    _mintAssetAndApproveForAdapter(defaultAmount, bob);

    vm.startPrank(bob);
    uint256 shares = adapter.deposit(defaultAmount, bob);
    uint256 assets = adapter.redeem(adapter.maxRedeem(bob), bob, bob);
    vm.stopPrank();

    // Pass the test if maxRedeem is smaller than deposit since round trips are impossible
    if (adapter.maxRedeem(bob) == defaultAmount) {
      assertLe(assets, defaultAmount, testId);
    }
  }

  function test__RT_deposit_withdraw() public virtual {
    _mintAssetAndApproveForAdapter(defaultAmount, bob);

    vm.startPrank(bob);
    uint256 shares1 = adapter.deposit(defaultAmount, bob);
    uint256 shares2 = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
    vm.stopPrank();

    // Pass the test if maxWithdraw is smaller than deposit since round trips are impossible
    if (adapter.maxWithdraw(bob) == defaultAmount) {
      assertGe(shares2, shares1, testId);
    }
  }

  function test__RT_mint_withdraw() public virtual {
    _mintAssetAndApproveForAdapter(adapter.previewMint(defaultAmount), bob);

    vm.startPrank(bob);
    uint256 assets = adapter.mint(defaultAmount, bob);
    uint256 shares = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
    vm.stopPrank();

    if (adapter.maxWithdraw(bob) == assets) {
      assertGe(shares, defaultAmount, testId);
    }
  }

  function test__RT_mint_redeem() public virtual {
    _mintAssetAndApproveForAdapter(adapter.previewMint(defaultAmount), bob);

    vm.startPrank(bob);
    uint256 assets1 = adapter.mint(defaultAmount, bob);
    uint256 assets2 = adapter.redeem(adapter.maxRedeem(bob), bob, bob);
    vm.stopPrank();

    if (adapter.maxRedeem(bob) == defaultAmount) {
      assertLe(assets2, assets1, testId);
    }
  }

  /*//////////////////////////////////////////////////////////////
                              PAUSE
    //////////////////////////////////////////////////////////////*/

  function test__pause() public virtual {
    _mintAssetAndApproveForAdapter(defaultAmount, bob);

    vm.prank(bob);
    adapter.deposit(defaultAmount, bob);

    uint256 oldTotalAssets = adapter.totalAssets();
    uint256 oldTotalSupply = adapter.totalSupply();

    adapter.pause();

    // We simply withdraw into the adapter
    // TotalSupply and Assets dont change
    assertApproxEqAbs(oldTotalAssets, adapter.totalAssets(), _delta_, "totalAssets");
    assertApproxEqAbs(oldTotalSupply, adapter.totalSupply(), _delta_, "totalSupply");
    assertApproxEqAbs(asset.balanceOf(address(adapter)), oldTotalAssets, _delta_, "asset balance");
    assertApproxEqAbs(iouBalance(), 0, _delta_, "iou balance");

    vm.startPrank(bob);
    // Deposit and mint are paused (maxDeposit/maxMint are set to 0 on pause)
    vm.expectRevert();
    adapter.deposit(defaultAmount, bob);

    vm.expectRevert();
    adapter.mint(defaultAmount, bob);

    // Withdraw and Redeem dont revert
    adapter.withdraw(defaultAmount / 10, bob, bob);
    adapter.redeem(defaultAmount / 10, bob, bob);
  }

  function testFail__pause_nonOwner() public virtual {
    vm.prank(alice);
    adapter.pause();
  }

  function test__unpause() public virtual {
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
    assertApproxEqAbs(oldTotalAssets, adapter.totalAssets(), _delta_, "totalAssets");
    assertApproxEqAbs(oldTotalSupply, adapter.totalSupply(), _delta_, "totalSupply");
    assertApproxEqAbs(asset.balanceOf(address(adapter)), 0, _delta_, "asset balance");
    assertApproxEqAbs(iouBalance(), oldIouBalance, _delta_, "iou balance");

    // Deposit and mint dont revert
    vm.startPrank(bob);
    adapter.deposit(defaultAmount, bob);
    adapter.mint(defaultAmount, bob);
  }

  function testFail__unpause_nonOwner() public virtual {
    adapter.pause();

    vm.prank(alice);
    adapter.unpause();
  }

  /*//////////////////////////////////////////////////////////////
                              HARVEST
    //////////////////////////////////////////////////////////////*/

  event StrategyExecuted();
  event Harvested();

  function test__harvest() public virtual {
    uint256 performanceFee = 1e16;
    uint256 hwm = 1e9;
    _mintAssetAndApproveForAdapter(defaultAmount, bob);

    vm.prank(bob);
    adapter.deposit(defaultAmount, bob);

    uint256 oldTotalAssets = adapter.totalAssets();
    adapter.setPerformanceFee(performanceFee);
    increasePricePerShare(raise);

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

  /*//////////////////////////////////////////////////////////////
                        HARVEST COOLDOWN
    //////////////////////////////////////////////////////////////*/

  event HarvestCooldownChanged(uint256 oldCooldown, uint256 newCooldown);

  function test__setHarvestCooldown() public virtual {
    vm.expectEmit(false, false, false, true, address(adapter));
    emit HarvestCooldownChanged(0, 1 hours);
    adapter.setHarvestCooldown(1 hours);

    assertEq(adapter.harvestCooldown(), 1 hours);
  }

  function testFail__setHarvestCooldown_nonOwner() public virtual {
    vm.prank(alice);
    adapter.setHarvestCooldown(1 hours);
  }

  function testFail__setHarvestCooldown_invalid_fee() public virtual {
    adapter.setHarvestCooldown(2 days);
  }

  /*//////////////////////////////////////////////////////////////
                            MANAGEMENT FEE
    //////////////////////////////////////////////////////////////*/

  event PerformanceFeeChanged(uint256 oldFee, uint256 newFee);

  function test__setPerformanceFee() public virtual {
    vm.expectEmit(false, false, false, true, address(adapter));
    emit PerformanceFeeChanged(0, 1e16);
    adapter.setPerformanceFee(1e16);

    assertEq(adapter.performanceFee(), 1e16);
  }

  function testFail__setPerformanceFee_nonOwner() public virtual {
    vm.prank(alice);
    adapter.setPerformanceFee(1e16);
  }

  function testFail__setPerformanceFee_invalid_fee() public virtual {
    adapter.setPerformanceFee(3e17);
  }

  /*//////////////////////////////////////////////////////////////
                              CLAIM
    //////////////////////////////////////////////////////////////*/

  // OPTIONAL
  function test__claim() public virtual {}

  /*//////////////////////////////////////////////////////////////
                              PERMIT
    //////////////////////////////////////////////////////////////*/

  function test__permit() public {
    uint256 privateKey = 0xBEEF;
    address owner = vm.addr(privateKey);

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      privateKey,
      keccak256(
        abi.encodePacked(
          "\x19\x01",
          adapter.DOMAIN_SEPARATOR(),
          keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(0xCAFE), 1e18, 0, block.timestamp))
        )
      )
    );

    adapter.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);

    assertEq(adapter.allowance(owner, address(0xCAFE)), 1e18, "allowance");
    assertEq(adapter.nonces(owner), 1, "nonce");
  }
}
