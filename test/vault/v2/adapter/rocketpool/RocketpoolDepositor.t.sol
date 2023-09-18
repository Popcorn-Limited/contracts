// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";

import {RocketpoolAdapter, RocketStorageInterface, RocketTokenRETHInterface, RocketDepositPoolInterface, RocketDepositSettingsInterface} from "../../../../../src/vault/v2/adapter/rocketpool/RocketpoolAdapter.sol";
import {RocketpoolDepositor} from "../../../../../src/vault/v2/strategies/rocketpool/RocketpoolDepositor.sol";

import {RocketpoolTestConfigStorage, ITestConfigStorage, AdapterConfig, ProtocolConfig} from "./RocketpoolTestConfigStorage.sol";
import {IERC20, IBaseAdapter, BaseAdapterTest} from "../../base/BaseStrategyTest.sol";

// import {IPermissionRegistry, Permission} from "../../../../../src/interfaces/vault/IPermissionRegistry.sol";

contract RocketpoolDepositorTest is BaseAdapterTest {
    using Math for uint256;

    function setUp() public {
        testConfigStorage = ITestConfigStorage(
            address(new RocketpoolTestConfigStorage())
        );

        _setUpBaseTest(0);
    }

    function _setUpStrategy(
        uint256 i_,
        address owner_
    ) internal override returns (address) {
        address strategy = Clones.clone(address(new RocketpoolDepositor()));

        AdapterConfig memory adapterConfig = RocketpoolTestConfigStorage(
            address(testConfigStorage)
        ).getAdapterConfig(i_);
        ProtocolConfig memory protocolConfig = RocketpoolTestConfigStorage(
            address(testConfigStorage)
        ).getProtocolConfig(i_);

        vm.prank(owner_);
        IBaseAdapter(strategy).initialize(adapterConfig, protocolConfig);

        return strategy;
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        // testConfigStorage = ITestConfigStorage(
        //     address(new RocketpoolTestConfigStorage())
        // );
        // (address _uniRouter, uint24 _uniSwapFee, string memory _network) = abi
        //     .decode(
        //         testConfigStorage.getTestConfig(0),
        //         (address, uint24, string)
        //     );
        // BaseVaultConfig memory baseVaultConfig = BaseVaultConfig({
        //     asset_: WETH,
        //     fees: VaultFees({
        //         deposit: 0,
        //         withdrawal: 0,
        //         management: 0,
        //         performance: 0
        //     }),
        //     feeRecipient: address(this),
        //     depositLimit: 0,
        //     owner: address(this),
        //     protocolOwner: address(this),
        //     name: "RocketpoolVault"
        // });
        // AdapterConfig memory adapterConfig = AdapterConfig({
        //     underlying: WETH,
        //     lpToken: IERC20(address(0)),
        //     useLpToken: false,
        //     rewardTokens: rewardTokens,
        //     owner: address(this)
        // });
        // ProtocolConfig memory protocolConfig = ProtocolConfig({
        //     registry: address(0),
        //     protocolInitData: abi.encode(_uniRouter, _uniSwapFee)
        // });
        // address depositor = Clones.clone(address(new RocketpoolDepositor()));
        // IBaseAdapter _strategy = IBaseAdapter(depositor);
        // adapterConfig.useLpToken = true;
        // vm.expectRevert(
        //     abi.encodeWithSelector(
        //         RocketpoolAdapter.LpTokenNotSupported.selector
        //     )
        // );
        // _strategy.initialize(adapterConfig, protocolConfig);
        // vm.mockCall(
        //     address(rocketStorage),
        //     abi.encodeWithSelector(
        //         rocketStorage.getAddress.selector,
        //         keccak256(
        //             abi.encodePacked("contract.address", "rocketDepositPool")
        //         )
        //     ),
        //     abi.encode(address(0))
        // );
        // adapterConfig.useLpToken = false;
        // vm.expectRevert(
        //     abi.encodeWithSelector(RocketpoolAdapter.InvalidAddress.selector)
        // );
        // _strategy.initialize(adapterConfig, protocolConfig);
        // vm.clearMockedCalls();
        // vm.mockCall(
        //     address(rocketStorage),
        //     abi.encodeWithSelector(
        //         rocketStorage.getAddress.selector,
        //         keccak256(
        //             abi.encodePacked("contract.address", "rocketTokenRETH")
        //         )
        //     ),
        //     abi.encode(address(0))
        // );
        // adapterConfig.useLpToken = false;
        // vm.expectRevert(
        //     abi.encodeWithSelector(RocketpoolAdapter.InvalidAddress.selector)
        // );
        // _strategy.initialize(adapterConfig, protocolConfig);
        // vm.clearMockedCalls();
        // address rocketTokenRETHAddress = rocketStorage.getAddress(
        //     keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        // );
        // rocketTokenRETH = RocketTokenRETHInterface(rocketTokenRETHAddress);
        // _strategy.initialize(adapterConfig, protocolConfig);
        // assertEq(
        //     rocketTokenRETH.allowance(address(_strategy), address(_uniRouter)),
        //     type(uint256).max,
        //     "allowance"
        // );
        // assertEq(
        //     rocketTokenRETH.allowance(
        //         address(_strategy),
        //         rocketTokenRETHAddress
        //     ),
        //     type(uint256).max,
        //     "allowance"
        // );
    }

    /*//////////////////////////////////////////////////////////////
                          TOTAL ASSETS
    //////////////////////////////////////////////////////////////*/

    /// @dev - This MUST be overriden to test that totalAssets adds up the the expected values
    function test__totalAssets() public virtual {}

    /*//////////////////////////////////////////////////////////////
                              PAUSE
    //////////////////////////////////////////////////////////////*/

    function test__unpause() public override {
        // _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);
        // vm.prank(bob);
        // vault.deposit(defaultAmount, bob);
        // uint256 oldTotalAssets = vault.totalAssets();
        // uint256 oldTotalSupply = vault.totalSupply();
        // uint256 oldIouBalance = iouBalance();
        // IBaseAdapter(vault.strategy()).pause();
        // IBaseAdapter(vault.strategy()).unpause();
        // uint256 depositFee = oldTotalAssets.mulDiv(
        //     rocketDepositSettings.getDepositFee(),
        //     1 ether,
        //     Math.Rounding.Up
        // );
        // // We simply deposit back into the external protocol
        // // TotalSupply and Assets dont change
        // assertApproxEqAbs(
        //     oldTotalAssets,
        //     vault.totalAssets(),
        //     depositFee,
        //     "totalAssets"
        // );
        // assertApproxEqAbs(
        //     oldTotalSupply,
        //     vault.totalSupply(),
        //     _delta_,
        //     "totalSupply"
        // );
        // assertApproxEqAbs(
        //     asset.balanceOf(address(strategy)),
        //     0,
        //     _delta_,
        //     "asset balance"
        // );
        // assertApproxEqAbs(
        //     iouBalance(),
        //     oldIouBalance,
        //     depositFee,
        //     "iou balance"
        // );
        // // Deposit and mint dont revert
        // vm.startPrank(bob);
        // vault.deposit(defaultAmount, bob);
        // vault.mint(defaultAmount, bob);
    }

    /*//////////////////////////////////////////////////////////////
                              HARVEST
    //////////////////////////////////////////////////////////////*/
    function test__harvest() public override {}

    function test__disable_auto_harvest() public override {}

    function test__setHarvestCooldown() public override {}

    function test__setPerformanceFee() public override {}
}
