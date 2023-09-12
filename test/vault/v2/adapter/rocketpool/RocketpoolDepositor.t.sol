// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import { Test } from "forge-std/Test.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";

import {
  RocketpoolAdapter,
  RocketStorageInterface,
  RocketTokenRETHInterface,
  RocketDepositPoolInterface,
  RocketDepositSettingsInterface
} from "../../../../../src/vault/v2/adapter/rocketpool/RocketpoolAdapter.sol";

import {
  VaultFees,
  BaseVaultConfig,
  SingleStrategyVault
} from "../../../../../src/vault/v2/vaults/SingleStrategyVault.sol";
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

  IBaseAdapter public strategy;
  IPermissionRegistry public permissionRegistry;
  RocketTokenRETHInterface public rocketTokenRETH;

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

    uint256 forkId = vm.createSelectFork(vm.rpcUrl(_network), 18104376);
    vm.selectFork(forkId);

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

    testConfigStorage = ITestConfigStorage(address(new RocketpoolTestConfigStorage()));

    RocketStorageInterface rocketStorage = RocketStorageInterface(_rocketStorageAddress);
    address rocketDepositPoolAddress = rocketStorage.getAddress(
      keccak256(abi.encodePacked("contract.address", "rocketDepositPool"))
    );
    RocketDepositPoolInterface rocketDepositPool = RocketDepositPoolInterface(rocketDepositPoolAddress);

    address rocketDepositSettingsAddress = rocketStorage.getAddress(
      keccak256(abi.encodePacked("contract.address", "rocketDAOProtocolSettingsDeposit"))
    );
    RocketDepositSettingsInterface rocketDepositSettings = RocketDepositSettingsInterface(
      rocketDepositSettingsAddress
    );

    address rocketTokenRETHAddress = rocketStorage.getAddress(
      keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
    );
    rocketTokenRETH = RocketTokenRETHInterface(rocketTokenRETHAddress);

    BaseVaultConfig memory baseVaultConfig = BaseVaultConfig({
      asset_: IERC20(_wETH),
      fees: VaultFees({
        deposit: 0,
        withdrawal: 0,
        management: 0,
        performance: 0
      }),
      feeRecipient: address(this),
      depositLimit: rocketDepositPool.getMaximumDepositAmount(),
      owner: address(this),
      protocolOwner: address(this),
      name: "RocketpoolVault"
    });

    address depositor = Clones.clone(address(new RocketpoolDepositor()));
    strategy = IBaseAdapter(depositor);
    strategy.initialize(adapterConfig, protocolConfig);

    minFuzz = rocketDepositSettings.getMinimumDeposit() * 10;

    setUpBaseTest(
      IERC20(_wETH),
      address(new SingleStrategyVault()),
      address(permissionRegistry),
      10,
      "Rocketpool ",
      true
    );

    defaultAmount = 1e17;
    maxAssets = rocketDepositPool.getMaximumDepositAmount() / 100;
    maxShares = maxAssets / 2;


    vm.label(address(asset), "asset");
    vm.label(address(this), "test");
    strategy.addVault(address(adapter));

    adapter.initialize(baseVaultConfig, address(strategy));
  }

  /*//////////////////////////////////////////////////////////////
                          HELPERS
    //////////////////////////////////////////////////////////////*/
  function iouBalance() public view override returns (uint256) {
    return rocketTokenRETH.balanceOf(address(strategy));
  }


  /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

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

    BaseVaultConfig memory baseVaultConfig = BaseVaultConfig({
      asset_: IERC20(_wETH),
      fees: VaultFees({
        deposit: 0,
        withdrawal: 0,
        management: 0,
        performance: 0
      }),
      feeRecipient: address(this),
      depositLimit: 0,
      owner: address(this),
      protocolOwner: address(this),
      name: "RocketpoolVault"
    });

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

    address depositor = Clones.clone(address(new RocketpoolDepositor()));
    IBaseAdapter _strategy = IBaseAdapter(depositor);

    RocketStorageInterface rocketStorage = RocketStorageInterface(_rocketStorageAddress);


    adapterConfig.useLpToken = true;
    vm.expectRevert(abi.encodeWithSelector(RocketpoolAdapter.LpTokenNotSupported.selector));
    _strategy.initialize(adapterConfig, protocolConfig);

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
    _strategy.initialize(adapterConfig, protocolConfig);
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
    _strategy.initialize(adapterConfig, protocolConfig);
    vm.clearMockedCalls();


    address rocketTokenRETHAddress = rocketStorage.getAddress(
      keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
    );

    rocketTokenRETH = RocketTokenRETHInterface(rocketTokenRETHAddress);

    _strategy.initialize(adapterConfig, protocolConfig);
    assertEq(rocketTokenRETH.allowance(address(_strategy), address(_uniRouter)), type(uint256).max, "allowance");
    assertEq(rocketTokenRETH.allowance(address(_strategy), rocketTokenRETHAddress), type(uint256).max, "allowance");
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

    IBaseAdapter(adapter.strategy()).pause();
    IBaseAdapter(adapter.strategy()).unpause();

    // We simply deposit back into the external protocol
    // TotalSupply and Assets dont change
//    assertApproxEqAbs(
//      oldTotalAssets,
//      adapter.totalAssets(),
//      _delta_,
//      "totalAssets"
//    );
    assertApproxEqAbs(
      oldTotalSupply,
      adapter.totalSupply(),
      _delta_,
      "totalSupply"
    );
    assertApproxEqAbs(
      asset.balanceOf(address(strategy)),
      0,
      _delta_,
      "asset balance"
    );
    //assertApproxEqAbs(iouBalance(), oldIouBalance, _delta_, "iou balance");

    // Deposit and mint dont revert
    vm.startPrank(bob);
    adapter.deposit(defaultAmount, bob);
    adapter.mint(defaultAmount, bob);
  }

  /*//////////////////////////////////////////////////////////////
                              HARVEST
    //////////////////////////////////////////////////////////////*/
  function test__harvest() public override {}
  function test__disable_auto_harvest() public override {}
  function test__setHarvestCooldown() public override {}
  function test__setPerformanceFee() public override {}
}
