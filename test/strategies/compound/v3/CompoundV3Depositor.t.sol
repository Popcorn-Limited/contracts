// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {CompoundV3Depositor, IERC20} from "../../../../src/strategies/compound/v3/CompoundV3Depositor.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../../BaseStrategyTest.sol";

contract CompoundV3DepositorTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/compound/v3/CompoundV3DepositorTestConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        CompoundV3Depositor strategy = new CompoundV3Depositor();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(json_.readAddress(string.concat(".configs[", index_, "].specific.cToken")))
        );

        return IBaseStrategy(address(strategy));
    }

    function _increasePricePerShare(uint256 amount) internal override {
        address cToken = address(CompoundV3Depositor(address(strategy)).cToken());
        _mintAsset(IERC20(testConfig.asset).balanceOf(cToken) + amount, cToken);
    }
}
