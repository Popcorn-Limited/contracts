// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {CompoundV2Depositor, IERC20} from "../../../../src/strategies/compound/v2/CompoundV2Depositor.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../../BaseStrategyTest.sol";

contract CompoundV2DepositorTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/compound/v2/CompoundV2DepositorTestConfig.json"
        );
    }

    function _setUpStrategy(
        string memory json_,
        string memory index_,
        TestConfig memory testConfig_
    ) internal override returns (IBaseStrategy) {
        CompoundV2Depositor strategy = new CompoundV2Depositor();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            false,
            abi.encode(
                json_.readAddress(
                    string.concat(".configs[", index_, "].specific.cToken")
                ),
                json_.readAddress(
                    string.concat(".configs[", index_, "].specific.comptroller")
                )
            )
        );

        return IBaseStrategy(address(strategy));
    }

    function _increasePricePerShare(uint256 amount) internal override {
        address cToken = address(
            CompoundV2Depositor(address(strategy)).cToken()
        );
        deal(
            testConfig.asset,
            cToken,
            IERC20(testConfig.asset).balanceOf(cToken) + amount
        );
    }
}
