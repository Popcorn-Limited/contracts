// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {AaveV3Depositor, IERC20} from "../../../src/strategies/aave/aaveV3/AaveV3Depositor.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";

contract AaveV3DepositorTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/aave/AaveV3DepositorTestConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        AaveV3Depositor strategy = new AaveV3Depositor();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(json_.readAddress(string.concat(".configs[", index_, "].specific.aaveDataProvider")))
        );

        vm.label(json_.readAddress(string.concat(".configs[", index_, "].specific.aToken")), "aToken");

        return IBaseStrategy(address(strategy));
    }

    function _increasePricePerShare(uint256 amount) internal override {
        address aToken = address(AaveV3Depositor(address(strategy)).aToken());
        deal(testConfig.asset, aToken, IERC20(testConfig.asset).balanceOf(aToken) + amount);
    }
}
