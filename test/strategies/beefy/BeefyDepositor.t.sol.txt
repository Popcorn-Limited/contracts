// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BeefyDepositor, IBeefyVault, IERC20} from "../../../src/strategies/beefy/BeefyDepositor.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";

contract BeefyDepositorTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/beefy/BeefyDepositorTestConfig.json"
        );
    }

    function _setUpStrategy(
        string memory json_,
        string memory index_,
        TestConfig memory testConfig_
    ) internal override returns (IBaseStrategy) {
        BeefyDepositor strategy = new BeefyDepositor();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(
                json_.readAddress(
                    string.concat(".configs[", index_, "].specific.beefyVault")
                )
            )
        );

        return IBaseStrategy(address(strategy));
    }

    function _increasePricePerShare(uint256 amount) internal override {
        IBeefyVault beefyVault = BeefyDepositor(address(strategy)).beefyVault();

        deal(
            testConfig.asset,
            address(beefyVault),
            IERC20(testConfig.asset).balanceOf(address(beefyVault)) + amount
        );
        beefyVault.earn();
    }
}
