// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";

import {RocketpoolAdapter, RocketStorageInterface, RocketTokenRETHInterface, RocketDepositPoolInterface, RocketDepositSettingsInterface} from "../../../../../src/vault/v2/adapter/rocketpool/RocketpoolAdapter.sol";
import {RocketpoolDepositor} from "../../../../../src/vault/v2/strategies/rocketpool/RocketpoolDepositor.sol";
import {IOwned} from "../../../../../src/vault/v2/base/interfaces/IOwned.sol";

import {RocketpoolTestConfigStorage, ITestConfigStorage, AdapterConfig, ProtocolConfig} from "./RocketpoolTestConfigStorage.sol";
import {IERC20, IBaseAdapter, BaseAdapterTest} from "../../base/BaseStrategyTest.sol";

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
        AdapterConfig memory adapterConfig = RocketpoolTestConfigStorage(
            address(testConfigStorage)
        ).getAdapterConfig(i_);
        ProtocolConfig memory protocolConfig = RocketpoolTestConfigStorage(
            address(testConfigStorage)
        ).getProtocolConfig(i_);

        address strategy = Clones.clone(address(new RocketpoolDepositor()));

        // --- TEST SUCCESSFUL INIT ---
        vm.prank(owner);
        IBaseAdapter(strategy).initialize(adapterConfig, protocolConfig);

        // Verify Generic Config
        IERC20 memory _rewardTokens = strategy.rewardTokens();

        assertEq(IOwned(address(strategy)).owner(), owner);
        assertEq(strategy.underlying(), adapterConfig.underlying);
        assertEq(strategy.lpToken(), address(adapterConfig.lpToken));
        assertEq(strategy.useLpToken(), address(adapterConfig.useLpToken));
        assertEq(_rewardTokens.length, adapterConfig.rewardTokens.length);
        assertEq(
            address(_rewardTokens[0]),
            address(adapterConfig.rewardTokens[0])
        );

        // Verify Protocol Specific Config

        (address _weth, address _uniRouter, uint24 _uniSwapFee) = abi.decode(
            protocolConfig.protocolInitData,
            (address, address, uint24)
        );
        assertEq(
            address(RocketpoolDepositor(address(strategy)).rocketStorage()),
            protocolConfig.registry
        );
        assertEq(address(RocketpoolDepositor(address(strategy)).WETH()), _weth);
        assertEq(
            address(RocketpoolDepositor(address(strategy)).uniSwapFee()),
            _uniRouter
        );
        assertEq(
            uint24(RocketpoolDepositor(address(strategy)).uniSwapFee()),
            _uniSwapFee
        );

        // Verify Allowances
        assertEq(
            rocketTokenRETH.allowance(address(strategy), address(_uniRouter)),
            type(uint256).max,
            "allowance"
        );
        assertEq(
            rocketTokenRETH.allowance(
                address(_strategy),
                rocketTokenRETHAddress
            ),
            type(uint256).max,
            "allowance"
        );

        // ------------------------
        // ------------------------
        // --- TEST FAILED INIT ---

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
        IBaseAdapter(strategy).initialize(adapterConfig, protocolConfig);

        // Reset faulty Config
        adapterConfig.useLpToken = false;

        // ----------------------------------------------------------------------
        // EXPECT ERROR - InvalidAddress (rocketDepositPoolAddress == address(0))

        // Set faulty Config
        vm.mockCall(
            address(rocketStorage),
            abi.encodeWithSelector(
                rocketStorage.getAddress.selector,
                keccak256(
                    abi.encodePacked("contract.address", "rocketDepositPool")
                )
            ),
            abi.encode(address(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                RocketpoolAdapter.LpTokenNotSupported.selector
            )
        );
        IBaseAdapter(strategy).initialize(adapterConfig, protocolConfig);

        // Reset faulty Config
        vm.clearMockedCalls();

        // ----------------------------------------------------------------------
        // EXPECT ERROR - InvalidAddress (rocketTokenRETHAddress == address(0))

        // Set faulty Config
        vm.mockCall(
            address(rocketStorage),
            abi.encodeWithSelector(
                rocketStorage.getAddress.selector,
                keccak256(
                    abi.encodePacked("contract.address", "rocketTokenRETH")
                )
            ),
            abi.encode(address(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                RocketpoolAdapter.LpTokenNotSupported.selector
            )
        );
        IBaseAdapter(strategy).initialize(adapterConfig, protocolConfig);

        // Reset faulty Config
        vm.clearMockedCalls();

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          TOTAL ASSETS
    //////////////////////////////////////////////////////////////*/

    /// @dev - This MUST be overriden to test that totalAssets adds up the the expected values
    function test__totalAssets() public override {
        // TODO test totalAssets after deposit and than after increase in underlying balance
    }

    /*//////////////////////////////////////////////////////////////
                              HARVEST
    //////////////////////////////////////////////////////////////*/
    function test__harvest() public override {}

    function test__disable_auto_harvest() public override {}

    function test__setHarvestCooldown() public override {}

    function test__setPerformanceFee() public override {}
}
