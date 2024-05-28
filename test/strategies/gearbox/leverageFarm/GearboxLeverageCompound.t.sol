// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {GearboxLeverageFarmCompoundV2} from
    "../../../../src/strategies/gearbox/leverageFarm/compound/GearboxLeverageFarmCompoundV2.sol";
import {ILeverageAdapter} from "../../../../src/strategies/gearbox/leverageFarm/IGearboxV3.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, IERC20} from "../../BaseStrategyTest.sol";

struct GearboxValues {
    address creditFacade;
    address creditManager;
    address strategyAdapter;
}

contract GearboxLeverageFarmCompoundTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/gearbox/leverageFarm/GearboxLeverageTestConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        GearboxLeverageFarmCompoundV2 strategy = new GearboxLeverageFarmCompoundV2();

        // Read strategy init values
        GearboxValues memory gearboxValues =
            abi.decode(json_.parseRaw(string.concat(".configs[", index_, "].specific.init")), (GearboxValues));

        strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(gearboxValues.creditFacade, gearboxValues.creditManager, gearboxValues.strategyAdapter)
        );

        return IBaseStrategy(address(strategy));
    }

    // function _increasePricePerShare(uint256 amount) internal override {
    //     address aToken = address(AaveV3Depositor(address(strategy)).aToken());
    //     deal(
    //         testConfig.asset,
    //         aToken,
    //         IERC20(testConfig.asset).balanceOf(aToken) + amount
    //     );
    // }

    /*//////////////////////////////////////////////////////////////
                            ADJUST LEVERAGE
    //////////////////////////////////////////////////////////////*/

    function test__adjustLeverage() public {
        _mintAsset(testConfig.defaultAmount, bob);

        vm.prank(bob);
        IERC20(testConfig.asset).approve(address(strategy), testConfig.defaultAmount);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        ILeverageAdapter(address(strategy)).adjustLeverage(1, abi.encode(testConfig.asset, testConfig.defaultAmount));
    }
}
