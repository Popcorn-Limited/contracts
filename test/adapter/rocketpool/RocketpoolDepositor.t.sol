// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {
    RocketpoolAdapter,
    IRocketStorage,
    IrETH,
    IRocketNetworkBalances
} from "../../../src/adapter/rocketpool/RocketpoolAdapter.sol";
import {IOwned} from "../../../src/base/interfaces/IOwned.sol";
import {IERC20, IBaseAdapter, BaseStrategyTest} from "../../base/BaseStrategyTest.sol";
import {RocketpoolDepositor} from "../../../src/strategies/rocketpool/RocketpoolDepositor.sol";
import {RocketpoolTestConfigStorage, ITestConfigStorage, AdapterConfig} from "./RocketpoolTestConfigStorage.sol";

contract RocketpoolDepositorTest is BaseStrategyTest {
    using Math for uint256;

    IrETH public rETH = IrETH(0xae78736Cd615f374D3085123A210448E74Fc6393);

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

        vm.prank(owner_);
        IBaseAdapter(strategy).initialize(adapterConfig);

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

        IBaseAdapter _strategy = IBaseAdapter(
            Clones.clone(address(new RocketpoolDepositor()))
        );

        // --- TEST SUCCESSFUL INIT ---
        vm.prank(owner);
        _strategy.initialize(adapterConfig);

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


        // Verify Allowances
        assertEq(
            rETH.allowance(address(_strategy), RocketpoolAdapter(payable(address(_strategy))).uniRouter()),
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
        _strategy.initialize(adapterConfig);

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

        address rocketNetworkBalances = IRocketStorage(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46)
            .getAddress(keccak256(abi.encodePacked("contract.address", "rocketNetworkBalances"))
        );

        uint256 initialTotalEthBalance = IRocketNetworkBalances(rocketNetworkBalances).getTotalETHBalance();

        // Increase TotalAssets
        vm.mockCall(
            rocketNetworkBalances,
            abi.encodeWithSelector(
                IRocketNetworkBalances.getTotalETHBalance.selector
            ),
            abi.encode(initialTotalEthBalance * 100)
        );

        assertGt(strategy.totalAssets(), oldAssets);
        vm.clearMockedCalls();
    }
}
