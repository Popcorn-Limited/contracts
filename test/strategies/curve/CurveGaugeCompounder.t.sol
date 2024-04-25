// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {CurveGaugeCompounder, IERC20, CurveSwap} from "../../../src/strategies/curve/gauge/mainnet/CurveGaugeCompounder.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";

struct CurveGaugeInit {
    address gauge;
    address minter;
    address pool;
}

contract CurveGaugeCompounderTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/curve/CurveGaugeCompounderTestConfig.json"
        );
    }

    function _setUpStrategy(
        string memory json_,
        string memory index_,
        TestConfig memory testConfig_
    ) internal override returns (IBaseStrategy) {
        // Read strategy init values
        CurveGaugeInit memory curveInit = abi.decode(
            json_.parseRaw(
                string.concat(".configs[", index_, "].specific.init")
            ),
            (CurveGaugeInit)
        );

        // Deploy Strategy
        CurveGaugeCompounder strategy = new CurveGaugeCompounder();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            false,
            abi.encode(
                curveInit.gauge,
                curveInit.pool,
                curveInit.minter
            )
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
        address curveRouter_ = abi.decode(
            json_.parseRaw(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.curveRouter"
                )
            ),
            (address)
        );

        int128 indexIn_ = abi.decode(
            json_.parseRaw(
                string.concat(".configs[", index_, "].specific.harvest.indexIn")
            ),
            (int128)
        );

        uint256[] memory minTradeAmounts_ = abi.decode(
            json_.parseRaw(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.minTradeAmounts"
                )
            ),
            (uint256[])
        );

        address[] memory rewardTokens_ = abi.decode(
            json_.parseRaw(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.rewardTokens"
                )
            ),
            (address[])
        );

        CurveSwap[] memory swaps_ = abi.decode(
            json_.parseRaw(
                string.concat(".configs[", index_, "].specific.harvest.swaps")
            ),
            (CurveSwap[])
        );

        // Set harvest values
        CurveGaugeCompounder(strategy).setHarvestValues(
            curveRouter_,
            rewardTokens_,
            minTradeAmounts_,
            swaps_,
            indexIn_
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
