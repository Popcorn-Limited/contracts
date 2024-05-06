// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BalancerCompounder, IERC20, BatchSwapStep, IAsset, BalancerValues, HarvestValues, HarvestTradePath, TradePath} from "../../../src/strategies/balancer/BalancerCompounder.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";

contract BalancerCompounderTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/balancer/BalancerCompounderTestConfig.json"
        );
    }

    function _setUpStrategy(
        string memory json_,
        string memory index_,
        TestConfig memory testConfig_
    ) internal override returns (IBaseStrategy) {
        // Read strategy init values
        BalancerValues memory balancerValues_ = abi.decode(
            json_.parseRaw(
                string.concat(".configs[", index_, "].specific.init")
            ),
            (BalancerValues)
        );

        // Deploy Strategy
        BalancerCompounder strategy = new BalancerCompounder();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            false,
            abi.encode(balancerValues_)
        );

        // Set Harvest values
        _setHarvestValues(json_, index_, address(strategy));

        return IBaseStrategy(address(strategy));
    }

    function _setHarvestValues(
        string memory json_,
        string memory index_,
        address strategy
    ) internal {
        // Read harvest values
        HarvestValues memory harvestValues_ = abi.decode(
            json_.parseRaw(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.harvestValues"
                )
            ),
            (HarvestValues)
        );

        HarvestTradePath[] memory tradePaths_ = abi.decode(
            json_.parseRaw(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.tradePaths"
                )
            ),
            (HarvestTradePath[])
        );

        // Set harvest values
        BalancerCompounder(strategy).setHarvestValues(
            harvestValues_,
            tradePaths_
        );
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
                                HARVEST
    //////////////////////////////////////////////////////////////*/

    // function test__harvest() public override {
    //     _mintAssetAndApproveForStrategy(10000e18, bob);

    //     vm.prank(bob);
    //     strategy.deposit(10000e18, bob);

    //     uint256 oldTa = strategy.totalAssets();

    //     vm.roll(block.number + 1000000);
    //     vm.warp(block.timestamp + 15000000);
        
    //     strategy.harvest();

    //     assertGt(strategy.totalAssets(), oldTa);
    // }

    // function test__harvest_no_rewards() public {
    //     _mintAssetAndApproveForStrategy(100e18, bob);

    //     vm.prank(bob);
    //     strategy.deposit(100e18, bob);

    //     uint256 oldTa = strategy.totalAssets();

    //     strategy.harvest();

    //     assertEq(strategy.totalAssets(), oldTa);
    // }
}
