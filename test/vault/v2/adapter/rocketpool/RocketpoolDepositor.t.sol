// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
//
import {
  //IWETH,
  RocketpoolAdapter,
  RocketStorageInterface,
  RocketTokenRETHInterface
  //RocketDepositPoolInterface
} from "../../../../../src/vault/v2/adapter/rocketpool/RocketpoolAdapter.sol";
//import { PermissionRegistry } from "../../../../src/vault/PermissionRegistry.sol";
//import { MockStrategyClaimer } from "../../../utils/mocks/MockStrategyClaimer.sol";
import { RocketpoolDepositor } from "../../../../../src/vault/v2/strategies/rocketpool/RocketpoolDepositor.sol";
import { RocketpoolTestConfigStorage, RocketPoolTestConfig } from "./RocketpoolTestConfigStorage.sol";
import {
  Math,
  IERC20,
  IBaseAdapter,
  AdapterConfig,
  ProtocolConfig,
  BaseAdapterTest,
  ITestConfigStorage
} from "../../base/BaseAdapterTest.sol";
import { IPermissionRegistry, Permission } from "../../../../../src/interfaces/vault/IPermissionRegistry.sol";

contract RocketpoolDepositorTest is BaseAdapterTest {
  using Math for uint256;

  IPermissionRegistry public permissionRegistry;

  function setUp() public {
    testConfigStorage = ITestConfigStorage(address(new RocketpoolTestConfigStorage()));

    _setUpTest(testConfigStorage.getTestConfig(0));
  }

  function _setUpTest(bytes memory testConfig) internal {
    (
      address _rocketStorageAddress,
      address _wETH,
      address _uniRouter,
      uint24 _uniSwapFee,
      string memory _network
    ) = abi.decode(
      testConfig, (address, address, address , uint24, string)
    );

    uint256 forkId = vm.createSelectFork(vm.rpcUrl(_network));
    vm.selectFork(forkId);

//    wETH = IWETH(_wETH);
//    uniRouter = _uniRouter;
//    uniSwapFee = _uniSwapFee;
//    rocketStorage = RocketStorageInterface(_rocketStorageAddress);

//    // Endorse Beefy Vault
//    permissionRegistry = IPermissionRegistry(address(new PermissionRegistry(address(this))));
//    setPermission(_beefyVault, true, false);


    setUpBaseTest(
      IERC20(_wETH),
      address(new RocketpoolDepositor()),
      address(permissionRegistry),
      10,
      "Rocketpool ",
      true
    );

    vm.label(address(asset), "asset");
    vm.label(address(this), "test");

    AdapterConfig memory adapterConfig = AdapterConfig({
      underlying: IERC20(_wETH),
      lpToken: IERC20(address(0)),
      useLpToken: false,
      rewardTokens: rewardTokens,
      owner: address(this)
    });

    ProtocolConfig memory protocolConfig = ProtocolConfig({
      registry: address (0),
      protocolInitData: abi.encode(
        _rocketStorageAddress,
        _wETH,
        _uniRouter,
        _uniSwapFee
      )
    });

    adapter.initialize(adapterConfig, protocolConfig);
  }

  /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/
//

//
//  function iouBalance() public view override returns (uint256) {
//    return beefyBalanceCheck.balanceOf(address(adapter));
//  }

//  // Verify that totalAssets returns the expected amount
//  function verify_totalAssets() public override {
//    // Make sure totalAssets isnt 0
//    deal(address(asset), bob, defaultAmount);
//    vm.startPrank(bob);
//    asset.approve(address(adapter), defaultAmount);
//    adapter.deposit(defaultAmount, bob);
//    vm.stopPrank();
//
//    assertEq(
//      adapter.totalAssets(),
//      adapter.convertToAssets(adapter.totalSupply()),
//      string.concat("totalSupply converted != totalAssets", baseTestId)
//    );
//    assertEq(
//      adapter.totalAssets(),
//      iouBalance().mulDiv(beefyVault.balance(), beefyVault.totalSupply(), Math.Rounding.Down),
//      string.concat("totalAssets != beefy assets", baseTestId)
//    );
//  }
//
//  function setPermission(address target, bool endorsed, bool rejected) public {
//    address[] memory targets = new address[](1);
//    Permission[] memory permissions = new Permission[](1);
//    targets[0] = target;
//    permissions[0] = Permission(endorsed, rejected);
//    permissionRegistry.setPermissions(targets, permissions);
//  }
//
//  /*//////////////////////////////////////////////////////////////
//                          INITIALIZATION
//    //////////////////////////////////////////////////////////////*/

  function verify_adapterInit() public override {
    testConfigStorage = ITestConfigStorage(address(new RocketpoolTestConfigStorage()));
    (
      address _rocketStorageAddress,
      address _wETH,
      address _uniRouter,
      uint24 _uniSwapFee,
      string memory _network
    ) = abi.decode(
      testConfigStorage.getTestConfig(0), (address, address, address , uint24, string)
    );

    AdapterConfig memory adapterConfig = AdapterConfig({
      underlying: IERC20(_wETH),
      lpToken: IERC20(address(0)),
      useLpToken: false,
      rewardTokens: rewardTokens,
      owner: address(this)
    });

    ProtocolConfig memory protocolConfig = ProtocolConfig({
      registry: address (0),
      protocolInitData: abi.encode(
        _rocketStorageAddress,
        _wETH,
        _uniRouter,
        _uniSwapFee
      )
    });
    RocketStorageInterface rocketStorage = RocketStorageInterface(_rocketStorageAddress);


    adapterConfig.useLpToken = true;
    vm.expectRevert(abi.encodeWithSelector(RocketpoolAdapter.LpTokenNotSupported.selector));
    adapter.initialize(adapterConfig, protocolConfig);

    vm.mockCall(
      address(rocketStorage),
      abi.encodeWithSelector(
        rocketStorage.getAddress.selector,
        keccak256(abi.encodePacked("contract.address", "rocketDepositPool"))
      ),
      abi.encode(address (0))
    );
    adapterConfig.useLpToken = false;
    vm.expectRevert(abi.encodeWithSelector(RocketpoolAdapter.InvalidAddress.selector));
    adapter.initialize(adapterConfig, protocolConfig);
    vm.clearMockedCalls();

    vm.mockCall(
      address(rocketStorage),
      abi.encodeWithSelector(
        rocketStorage.getAddress.selector,
        keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
      ),
      abi.encode(address (0))
    );
    adapterConfig.useLpToken = false;
    vm.expectRevert(abi.encodeWithSelector(RocketpoolAdapter.InvalidAddress.selector));
    adapter.initialize(adapterConfig, protocolConfig);
    vm.clearMockedCalls();


    address rocketTokenRETHAddress = rocketStorage.getAddress(
      keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
    );
    RocketTokenRETHInterface rocketTokenRETH = RocketTokenRETHInterface(rocketTokenRETHAddress);

    adapter.initialize(adapterConfig, protocolConfig);
    assertEq(rocketTokenRETH.allowance(address(adapter), address(_uniRouter)), type(uint256).max, "allowance");
    assertEq(rocketTokenRETH.allowance(address(adapter), rocketTokenRETHAddress), type(uint256).max, "allowance");
  }


  /*//////////////////////////////////////////////////////////////
                    DEPOSIT/MINT/WITHDRAW/REDEEM
    //////////////////////////////////////////////////////////////*/


  function test__deposit(uint8 fuzzAmount) public override {
    testConfigStorage = ITestConfigStorage(address(new RocketpoolTestConfigStorage()));

    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);
    uint8 len = uint8(testConfigStorage.getTestConfigLength());
    for (uint8 i; i < len; i++) {
      if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

      _mintAssetAndApproveForAdapter(amount, bob);
      prop_deposit(bob, bob, amount, testId);

//      increasePricePerShare(raise);
//
//      _mintAssetAndApproveForAdapter(amount, bob);
//      prop_deposit(bob, alice, amount, testId);
    }
  }


//
//  function test__mint(uint8 fuzzAmount) public override {
//    testConfigStorage = ITestConfigStorage(address(new BeefyTestConfigStorage()));
//
//    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);
//    uint8 len = uint8(testConfigStorage.getTestConfigLength());
//    for (uint8 i; i < len; i++) {
//      if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));
//
//      _mintAssetAndApproveForAdapter(adapter.previewMint(amount), bob);
//      prop_mint(bob, bob, amount, testId);
//
//      increasePricePerShare(raise);
//
//      _mintAssetAndApproveForAdapter(adapter.previewMint(amount), bob);
//      prop_mint(bob, alice, amount, testId);
//    }
//  }
//
//  function test__withdraw(uint8 fuzzAmount) public override {
//    testConfigStorage = ITestConfigStorage(address(new BeefyTestConfigStorage()));
//
//    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);
//    uint8 len = uint8(testConfigStorage.getTestConfigLength());
//    for (uint8 i; i < len; i++) {
//      if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));
//
//      uint256 reqAssets = (adapter.previewMint(adapter.previewWithdraw(amount)) * 10) / 8;
//      _mintAssetAndApproveForAdapter(reqAssets, bob);
//      vm.prank(bob);
//      adapter.deposit(reqAssets, bob);
//      prop_withdraw(bob, bob, amount, testId);
//
//      _mintAssetAndApproveForAdapter(reqAssets, bob);
//      vm.prank(bob);
//      adapter.deposit(reqAssets, bob);
//
//      increasePricePerShare(raise);
//
//      vm.prank(bob);
//      adapter.approve(alice, type(uint256).max);
//      prop_withdraw(alice, bob, amount, testId);
//    }
//  }
//
//  function test__redeem(uint8 fuzzAmount) public override {
//    testConfigStorage = ITestConfigStorage(address(new BeefyTestConfigStorage()));
//
//    uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);
//    uint8 len = uint8(testConfigStorage.getTestConfigLength());
//    for (uint8 i; i < len; i++) {
//      if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));
//
//      uint256 reqAssets = (adapter.previewMint(amount) * 10) / 9;
//      _mintAssetAndApproveForAdapter(reqAssets, bob);
//      vm.prank(bob);
//      adapter.deposit(reqAssets, bob);
//      prop_redeem(bob, bob, amount, testId);
//
//      _mintAssetAndApproveForAdapter(reqAssets, bob);
//      vm.prank(bob);
//      adapter.deposit(reqAssets, bob);
//
//      increasePricePerShare(raise);
//
//      vm.prank(bob);
//      adapter.approve(alice, type(uint256).max);
//      prop_redeem(alice, bob, amount, testId);
//    }
//  }
//
//  /*//////////////////////////////////////////////////////////////
//                          ROUNDTRIP TESTS
//    //////////////////////////////////////////////////////////////*/
//
//  // NOTE - The beefy adapter suffers often from an off-by-one error which "steals" 1 wei from the user
//  function test__RT_deposit_withdraw() public override {
//    _mintAssetAndApproveForAdapter(defaultAmount, bob);
//
//    vm.startPrank(bob);
//    uint256 shares1 = adapter.deposit(defaultAmount, bob);
//    uint256 shares2 = adapter.withdraw(defaultAmount - 1, bob, bob);
//    vm.stopPrank();
//
//    assertGe(shares2, shares1, testId);
//  }
//
//  // NOTE - The beefy adapter suffers often from an off-by-one error which "steals" 1 wei from the user
//  function test__RT_mint_withdraw() public override {
//    _mintAssetAndApproveForAdapter(adapter.previewMint(defaultAmount), bob);
//
//    vm.startPrank(bob);
//    uint256 assets = adapter.mint(defaultAmount, bob);
//    uint256 shares = adapter.withdraw(assets - 1, bob, bob);
//    vm.stopPrank();
//
//    assertGe(shares, defaultAmount, testId);
//  }
//
//  /*//////////////////////////////////////////////////////////////
//                              PAUSE
//    //////////////////////////////////////////////////////////////*/
//
//  function test__unpause() public override {
//    _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);
//
//    vm.prank(bob);
//    adapter.deposit(defaultAmount, bob);
//
//    uint256 oldTotalAssets = adapter.totalAssets();
//    uint256 oldTotalSupply = adapter.totalSupply();
//    uint256 oldIouBalance = iouBalance();
//
//    adapter.pause();
//    adapter.unpause();
//
//    // We simply deposit back into the external protocol
//    // TotalSupply and Assets dont change
//    // @dev overriden _delta_
//    assertApproxEqAbs(oldTotalAssets, adapter.totalAssets(), 50, "totalAssets");
//    assertApproxEqAbs(oldTotalSupply, adapter.totalSupply(), 50, "totalSupply");
//    assertApproxEqAbs(asset.balanceOf(address(adapter)), 0, 50, "asset balance");
//    assertApproxEqRel(iouBalance(), oldIouBalance, 1, "iou balance");
//
//    // Deposit and mint dont revert
//    vm.startPrank(bob);
//    adapter.deposit(defaultAmount, bob);
//    adapter.mint(defaultAmount, bob);
//  }

  /*//////////////////////////////////////////////////////////////
                              CLAIM
    //////////////////////////////////////////////////////////////*/

//  function test__claim() public override {
//    testConfigStorage = ITestConfigStorage(address(new BeefyTestConfigStorage()));
//    strategy = IStrategy(address(new MockStrategyClaimer()));
//    createAdapter();
//    adapter.initialize(
//      abi.encode(asset, address(this), strategy, 0, sigs, ""),
//      externalRegistry,
//      testConfigStorage.getTestConfig(0)
//    );
//
//    _mintAssetAndApproveForAdapter(1000e18, bob);
//
//    vm.prank(bob);
//    adapter.deposit(1000e18, bob);
//
//    vm.warp(block.timestamp + 10 days);
//
//    vm.prank(bob);
//    adapter.withdraw(1, bob, bob);
//
//    address[] memory rewardTokens = IWithRewards(address(adapter)).rewardTokens();
//    assertEq(rewardTokens[0], beefyBooster.rewardToken());
//
//    assertGt(IERC20(rewardTokens[0]).balanceOf(address(adapter)), 0);
//  }
}
