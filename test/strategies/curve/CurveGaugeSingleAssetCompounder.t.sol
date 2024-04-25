// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {CurveGaugeSingleAssetCompounder, IERC20, CurveSwap} from "../../../src/strategies/curve/gauge/other/CurveGaugeSingleAssetCompounder.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";

struct CurveGaugeInit {
    address gauge;
    int128 indexIn;
    address lpToken;
}

contract CurveGaugeSingleAssetCompounderTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/curve/CurveGaugeSingleAssetCompounderTestConfig.json"
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
        CurveGaugeSingleAssetCompounder strategy = new CurveGaugeSingleAssetCompounder();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            false,
            abi.encode(curveInit.lpToken, curveInit.gauge, curveInit.indexIn)
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

        uint256 discountBps_ = abi.decode(
            json_.parseRaw(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.discountBps"
                )
            ),
            (uint256)
        );

        // Set harvest values
        CurveGaugeSingleAssetCompounder(strategy).setHarvestValues(
            curveRouter_,
            rewardTokens_,
            minTradeAmounts_,
            swaps_,
            discountBps_
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

    function test__withdraw(uint8 fuzzAmount) public override {
        uint len = json.readUint(".length");
        for (uint i; i < len; i++) {
            if (i > 0) _setUpBaseTest(i, path);

            uint256 amount = bound(
                fuzzAmount,
                testConfig.minDeposit,
                testConfig.maxDeposit
            );

            uint256 reqAssets = strategy.previewMint(
                strategy.previewWithdraw(amount)
            );
            _mintAssetAndApproveForStrategy(reqAssets, bob);
            vm.prank(bob);
            strategy.deposit(reqAssets, bob);

            emit log_named_uint(
                "discountBps",
                CurveGaugeSingleAssetCompounder(address(strategy)).discountBps()
            );

            emit log_named_uint(
                "gauge bal",
                IERC20(address(0x059E0db6BF882f5fe680dc5409C7adeB99753736))
                    .balanceOf(address(strategy))
            );

            emit log_named_uint(
                "totalSupply",
                CurveGaugeSingleAssetCompounder(address(strategy)).totalSupply()
            );

            emit log_named_uint(
                "strategy.maxWithdraw(bob)",
                strategy.maxWithdraw(bob)
            );

            prop_withdraw(
                bob,
                bob,
                strategy.maxWithdraw(bob),
                testConfig.testId
            );

            _mintAssetAndApproveForStrategy(reqAssets, bob);
            vm.prank(bob);
            strategy.deposit(reqAssets, bob);

            _increasePricePerShare(testConfig.defaultAmount);

            vm.prank(bob);
            strategy.approve(alice, type(uint256).max);

            prop_withdraw(
                alice,
                bob,
                strategy.maxWithdraw(bob),
                testConfig.testId
            );
        }
    }

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
