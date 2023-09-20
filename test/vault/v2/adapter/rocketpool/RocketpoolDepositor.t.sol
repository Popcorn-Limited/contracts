// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {
    RocketpoolAdapter,
    RocketStorageInterface,
    RocketTokenRETHInterface,
    RocketDepositPoolInterface,
    RocketDepositSettingsInterface,
    RocketNetworkBalancesInterface
} from "../../../../../src/vault/v2/adapter/rocketpool/RocketpoolAdapter.sol";
import {RocketpoolDepositor} from "../../../../../src/vault/v2/strategies/rocketpool/RocketpoolDepositor.sol";
import {IOwned} from "../../../../../src/vault/v2/base/interfaces/IOwned.sol";

import {RocketpoolTestConfigStorage, ITestConfigStorage, AdapterConfig, ProtocolConfig} from "./RocketpoolTestConfigStorage.sol";
import {IERC20, IBaseAdapter, BaseStrategyTest} from "../../base/BaseStrategyTest.sol";

contract RocketpoolDepositorTest is BaseStrategyTest {
    using Math for uint256;

    RocketTokenRETHInterface public rETH = RocketTokenRETHInterface(0xae78736Cd615f374D3085123A210448E74Fc6393);

    function setUp() public {
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

    function _setUpTestStorage() internal override returns (address) {
        return address(new RocketpoolTestConfigStorage());
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        AdapterConfig memory adapterConfig = RocketpoolTestConfigStorage(
            address(testConfigStorage)
        ).getAdapterConfig(0);
        ProtocolConfig memory protocolConfig = RocketpoolTestConfigStorage(
            address(testConfigStorage)
        ).getProtocolConfig(0);

        address rocketStorage = protocolConfig.registry;

        IBaseAdapter _strategy = IBaseAdapter(
            Clones.clone(address(new RocketpoolDepositor()))
        );

        // --- TEST SUCCESSFUL INIT ---
        vm.prank(owner);
        _strategy.initialize(adapterConfig, protocolConfig);

        // Verify Generic Config
        IERC20[] memory _rewardTokens = _strategy.getRewardTokens();

        assertEq(IOwned(address(_strategy)).owner(), owner);
        assertEq(
            address(_strategy.underlying()),
            address(adapterConfig.underlying)
        );
        assertEq(_strategy.lpToken(), address(adapterConfig.lpToken));
        assertEq(_strategy.useLpToken(), adapterConfig.useLpToken);
        assertEq(_rewardTokens.length, adapterConfig.rewardTokens.length);

        // Verify Protocol Specific Config

        (address _weth, address _uniRouter, uint24 _uniSwapFee) = abi.decode(
            protocolConfig.protocolInitData,
            (address, address, uint24)
        );
        assertEq(
            address(
                RocketpoolDepositor(payable(address(_strategy))).rocketStorage()
            ),
            protocolConfig.registry
        );
        assertEq(
            address(RocketpoolDepositor(payable(address(_strategy))).WETH()),
            _weth
        );
        assertEq(
            address(
                RocketpoolDepositor(payable(address(_strategy))).uniRouter()
            ),
            _uniRouter
        );
        assertEq(
            uint24(
                RocketpoolDepositor(payable(address(_strategy))).uniSwapFee()
            ),
            _uniSwapFee
        );

        // Verify Allowances
        assertEq(
            rETH.allowance(address(_strategy), address(_uniRouter)),
            type(uint256).max,
            "allowance"
        );

        // ------------------------
        // ------------------------
        // --- TEST FAILED INIT ---

        _strategy = IBaseAdapter(
            Clones.clone(address(new RocketpoolDepositor()))
        );

        vm.startPrank(owner);

        // -------------------------------------------------------
        // EXPECT ERROR - LpTokenNotSupported (useLpToken == true)

        // Set faulty Config
        adapterConfig.useLpToken = true;

        vm.expectRevert(
            abi.encodeWithSelector(
                RocketpoolAdapter.LpTokenNotSupported.selector
            )
        );
        _strategy.initialize(adapterConfig, protocolConfig);

        // Reset faulty Config
        adapterConfig.useLpToken = false;

        // ----------------------------------------------------------------------
        // EXPECT ERROR - InvalidAddress (rocketDepositPoolAddress == address(0))

        // Set faulty Config
        vm.mockCall(
            address(rocketStorage),
            abi.encodeWithSelector(
                RocketStorageInterface.getAddress.selector,
                keccak256(
                    abi.encodePacked("contract.address", "rocketDepositPool")
                )
            ),
            abi.encode(address(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(RocketpoolAdapter.InvalidAddress.selector)
        );
        _strategy.initialize(adapterConfig, protocolConfig);

        // Reset faulty Config
        vm.clearMockedCalls();

        // ----------------------------------------------------------------------
        // EXPECT ERROR - InvalidAddress (rocketTokenRETHAddress == address(0))

        // Set faulty Config
        vm.mockCall(
            address(rocketStorage),
            abi.encodeWithSelector(
                RocketStorageInterface.getAddress.selector,
                keccak256(
                    abi.encodePacked("contract.address", "rocketTokenRETH")
                )
            ),
            abi.encode(address(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(RocketpoolAdapter.InvalidAddress.selector)
        );
        _strategy.initialize(adapterConfig, protocolConfig);

        // Reset faulty Config
        vm.clearMockedCalls();

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          TOTAL ASSETS
    //////////////////////////////////////////////////////////////*/

    /// @dev - This MUST be overriden to test that totalAssets adds up the the expected values
    function test__totalAssets() public override {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount);

        uint256 oldAssets = strategy.totalAssets();

        assertApproxEqAbs(
            oldAssets,
            testConfig.defaultAmount,
            testConfig.depositDelta
        );

        assertEq(
            oldAssets,
            rETH.getEthValue(rETH.balanceOf(address(strategy)))
        );

        address rocketNetworkBalances = RocketStorageInterface(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46)
            .getAddress(keccak256(abi.encodePacked("contract.address", "rocketNetworkBalances"))
        );

        uint256 initialTotalEthBalance = RocketNetworkBalancesInterface(rocketNetworkBalances).getTotalETHBalance();

        // Increase TotalAssets
        vm.mockCall(
            rocketNetworkBalances,
            abi.encodeWithSelector(
                RocketNetworkBalancesInterface.getTotalETHBalance.selector
            ),
            abi.encode(initialTotalEthBalance * 100)
        );

        assertGt(strategy.totalAssets(), oldAssets);
        vm.clearMockedCalls();
    }
}
