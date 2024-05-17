// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {CurveGaugeSingleAssetCompounder, IERC20, CurveSwap} from "../../../src/strategies/curve/CurveGaugeSingleAssetCompounder.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";

struct CurveGaugeInit {
    address gauge;
    int128 indexIn;
    address lpToken;
    address pool;
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
            true,
            abi.encode(
                curveInit.lpToken,
                curveInit.pool,
                curveInit.gauge,
                curveInit.indexIn
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

        //Construct CurveSwap structs
        CurveSwap[] memory swaps_ = _getCurveSwaps(json_, index_);

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
            swaps_,
            discountBps_
        );
    }

    function _getCurveSwaps(
        string memory json_,
        string memory index_
    ) internal pure returns (CurveSwap[] memory) {
        uint256 swapLen = json_.readUint(
            string.concat(
                ".configs[",
                index_,
                "].specific.harvest.swaps.length"
            )
        );

        CurveSwap[] memory swaps_ = new CurveSwap[](swapLen);
        for (uint i; i < swapLen; i++) {
            // Read route and convert dynamic into fixed size array
            address[] memory route_ = json_.readAddressArray(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.swaps.structs[",
                    vm.toString(i),
                    "].route"
                )
            );
            address[11] memory route;
            for (uint n; n < 11; n++) {
                route[n] = route_[n];
            }

            // Read swapParams and convert dynamic into fixed size array
            uint256[5][5] memory swapParams;
            for (uint n = 0; n < 5; n++) {
                uint256[] memory swapParams_ = json_.readUintArray(
                    string.concat(
                        ".configs[",
                        index_,
                        "].specific.harvest.swaps.structs[",
                        vm.toString(i),
                        "].swapParams[",
                        vm.toString(n),
                        "]"
                    )
                );
                for (uint y; y < 5; y++) {
                    swapParams[n][y] = swapParams_[y];
                }
            }

            // Read pools and convert dynamic into fixed size array
            address[] memory pools_ = json_.readAddressArray(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.swaps.structs[",
                    vm.toString(i),
                    "].pools"
                )
            );
            address[5] memory pools;
            for (uint n = 0; n < 5; n++) {
                pools[n] = pools_[n];
            }

            // Construct the struct
            swaps_[i] = CurveSwap({
                route: route,
                swapParams: swapParams,
                pools: pools
            });
        }
        return swaps_;
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
                            OVERRIDEN TESTS
    //////////////////////////////////////////////////////////////*/

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

    // NOTE - Slippage here is higher than the usual delta
    function test__pause() public override {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        uint256 oldTotalAssets = strategy.totalAssets();

        vm.prank(address(this));
        strategy.pause();

        // We simply withdraw into the strategy
        // TotalSupply and Assets dont change
        assertApproxEqAbs(
            oldTotalAssets,
            strategy.totalAssets(),
            5.4e16,
            "totalAssets"
        );
        assertApproxEqAbs(
            IERC20(testConfig.asset).balanceOf(address(strategy)),
            oldTotalAssets,
            5.4e16,
            "asset balance"
        );
    }

    // NOTE - Slippage here is higher than the usual delta
    function test__unpause() public override {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount * 3, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount * 3, bob);

        uint256 oldTotalAssets = strategy.totalAssets();

        vm.prank(address(this));
        strategy.pause();

        vm.prank(address(this));
        strategy.unpause();

        // We simply deposit back into the external protocol
        // TotalAssets shouldnt change significantly besides some slippage or rounding errors
        assertApproxEqAbs(
            oldTotalAssets,
            strategy.totalAssets(),
            2e14,
            "totalAssets"
        );
        assertApproxEqAbs(
            IERC20(testConfig.asset).balanceOf(address(strategy)),
            0,
            testConfig.delta,
            "asset balance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                                HARVEST
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public override {
        _mintAssetAndApproveForStrategy(10000e18, bob);

        vm.prank(bob);
        strategy.deposit(10000e18, bob);

        uint256 oldTa = strategy.totalAssets();

        vm.warp(block.timestamp + 150_000);

        strategy.harvest(abi.encode(uint256(0)));

        assertGt(strategy.totalAssets(), oldTa);
    }

    function testFail__harvest_slippage_too_high() public {
        _mintAssetAndApproveForStrategy(10000e18, bob);

        vm.prank(bob);
        strategy.deposit(10000e18, bob);

        uint256 oldTa = strategy.totalAssets();

        vm.warp(block.timestamp + 150_000);

        strategy.harvest(abi.encode(uint256(5530379817425055987)));

        assertGt(strategy.totalAssets(), oldTa);
    }

    function testFail__harvest_no_rewards() public {
        _mintAssetAndApproveForStrategy(100e18, bob);

        vm.prank(bob);
        strategy.deposit(100e18, bob);

        uint256 oldTa = strategy.totalAssets();

        strategy.harvest(abi.encode(uint256(6e18)));

        assertEq(strategy.totalAssets(), oldTa);
    }
}
