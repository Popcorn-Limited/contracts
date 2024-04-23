// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {AuraCompounder, IERC20, BatchSwapStep, IAsset, AuraValues, HarvestValues, TradePath} from "../../../src/strategies/aura/AuraCompounder.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";

contract AuraCompounderTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/aura/AuraCompounderTestConfig.json"
        );
    }

    function _setUpStrategy(
        string memory json_,
        string memory index_,
        TestConfig memory testConfig_
    ) internal override returns (IBaseStrategy) {
        // Read strategy init values
        AuraValues memory auraValues_ = abi.decode(
            json_.parseRaw(
                string.concat(".configs[", index_, "].specific.init")
            ),
            (AuraValues)
        );

        // Deploy Strategy
        AuraCompounder strategy = new AuraCompounder();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            false,
            abi.encode(auraValues_)
        );

        _setHarvestValues(json_, index_, address(strategy));

        return IBaseStrategy(address(strategy));
    }

    function test__stuff() public {}

    function _setHarvestValues(
        string memory json_,
        string memory index_,
        address strategy
    ) internal {
        // Read harvest values
        // BatchSwapStep[][] memory swaps = abi.decode(
        //     json_.parseRaw(
        //         string.concat(".configs[", index_, "].specific.harvest.swaps")
        //     ),
        //     (BatchSwapStep[][])
        // );
        // IAsset[][] memory assets = abi.decode(
        //     json_.parseRaw(
        //         string.concat(".configs[", index_, "].specific.harvest.assets")
        //     ),
        //     (IAsset[][])
        // );
        // int256[][] memory limits = abi.decode(
        //     json_.parseRaw(
        //         string.concat(
        //             ".configs[",
        //             index_,
        //             "].specific.harvest.minTradeAmounts"
        //         )
        //     ),
        //     (int256[][])
        // );
        // uint256[] memory minTradeAmounts = abi.decode(
        //     json_.parseRaw(
        //         string.concat(
        //             ".configs[",
        //             index_,
        //             "].specific.harvest.minTradeAmounts"
        //         )
        //     ),
        //     (uint256[])
        // );

        // IERC20 baseAsset = IERC20(
        //     json_.readAddress(
        //         string.concat(
        //             ".configs[",
        //             index_,
        //             "].specific.harvest.baseAsset"
        //         )
        //     )
        // );
        // uint256 indexIn = json_.readUint(
        //     string.concat(".configs[", index_, "].specific.harvest.indexIn")
        // );
        // uint256 indexInUserData = json_.readUint(
        //     string.concat(
        //         ".configs[",
        //         index_,
        //         "].specific.harvest.indexInUserData"
        //     )
        // );
        // uint256 amountsInLen = json_.readUint(
        //     string.concat(
        //         ".configs[",
        //         index_,
        //         "].specific.harvest.amountsInLen"
        //     )
        // );

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

        TradePath memory tradePath0 = abi.decode(
            json_.parseRaw(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.tradePaths[0]"
                )
            ),
            (TradePath)
        );
        TradePath memory tradePath1 = abi.decode(
            json_.parseRaw(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.tradePaths[1]"
                )
            ),
            (TradePath)
        );

        TradePath[] memory tradePaths_ = abi.decode(
            json_.parseRaw(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.tradePaths"
                )
            ),
            (TradePath[])
        );

        emit log_uint(tradePaths_[0].amount[0]);
        emit log_address(tradePaths_[0].assets[0]);
        emit log_address(address(strategy));

        // TradePath[] memory tradePaths_ = new TradePath[](2);
        // tradePaths_[0] = tradePath0;
        // tradePaths_[1] = tradePath1;

        // Set harvest values
        AuraCompounder(strategy).setHarvestValues(harvestValues_, tradePaths_);
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

    function test__harvest() public override {
        _mintAssetAndApproveForStrategy(10000e18, bob);

        vm.prank(bob);
        strategy.deposit(10000e18, bob);

        uint256 oldTa = strategy.totalAssets();

        vm.roll(block.number + 100);
        vm.warp(block.timestamp + 1500);

        strategy.harvest();

        assertGt(strategy.totalAssets(), oldTa);
    }

    function test__harvest_no_rewards() public {
        _mintAssetAndApproveForStrategy(100e18, bob);

        vm.prank(bob);
        strategy.deposit(100e18, bob);

        uint256 oldTa = strategy.totalAssets();

        strategy.harvest();

        assertEq(strategy.totalAssets(), oldTa);
    }
}
