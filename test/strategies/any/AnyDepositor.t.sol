// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.0
pragma solidity ^0.8.25;

import {AnyDepositor, IERC20} from "src/strategies/AnyDepositor.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";
import {AnyBaseTest} from "./AnyBase.t.sol";
import {MockOracle} from "test/utils/mocks/MockOracle.sol";
import "forge-std/console.sol";


contract AnyDepositorTest is AnyBaseTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/any/AnyDepositorTestConfig.json"
        );
    }

    function _setUpStrategy(
        string memory json_,
        string memory index_,
        TestConfig memory testConfig_
    ) internal override returns (IBaseStrategy) {
        AnyDepositor _strategy = new AnyDepositor();
        MockOracle oracle = new MockOracle();

        yieldAsset = json_.readAddress(
            string.concat(".configs[", index_, "].specific.yieldAsset")
        );

        _strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(yieldAsset, address(oracle), uint256(10), uint256(0))
        );

        return IBaseStrategy(address(_strategy));
    }
}