// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.0
pragma solidity ^0.8.25;

import {AnyDepositorV2, IERC20} from "src/strategies/any/v2/AnyDepositorV2.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "test/strategies/BaseStrategyTest.sol";
import {AnyBaseTest} from "./AnyBase.t.sol";
import {MockOracle} from "test/mocks/MockOracle.sol";
import "forge-std/console.sol";

contract AnyDepositorV2Test is AnyBaseTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/any/v2/AnyDepositorTestConfig.json"
        );
        _setUpBase();
    }

    function _setUpStrategy(
        string memory json_,
        string memory index_,
        TestConfig memory testConfig_
    ) internal override returns (IBaseStrategy) {
        AnyDepositorV2 _strategy = new AnyDepositorV2();
        oracle = new MockOracle();

        yieldToken = json_.readAddress(
            string.concat(".configs[", index_, "].specific.yieldToken")
        );

        _strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(yieldToken, address(oracle), uint256(0), initialTargets, initialAllowances)
        );

        return IBaseStrategy(address(_strategy));
    }
}
