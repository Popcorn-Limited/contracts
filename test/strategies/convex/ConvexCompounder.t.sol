// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {ConvexCompounder, IERC20, CurveSwap} from "../../../src/strategies/convex/ConvexCompounder.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";

struct ConvexInit {
    address convexBooster;
    address curvePool;
    uint256 pid;
}

contract ConvexCompounderTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/convex/ConvexCompounderTestConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        // Read strategy init values
        ConvexInit memory convexInit =
            abi.decode(json_.parseRaw(string.concat(".configs[", index_, "].specific.init")), (ConvexInit));

        // Deploy Strategy
        ConvexCompounder strategy = new ConvexCompounder();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(convexInit.convexBooster, convexInit.curvePool, convexInit.pid)
        );

        // Set Harvest values
        _setHarvestValues(json_, index_, address(strategy));

        return IBaseStrategy(address(strategy));
    }

    function _setHarvestValues(string memory json_, string memory index_, address strategy) internal {
        // Read harvest values
        address curveRouter_ =
            abi.decode(json_.parseRaw(string.concat(".configs[", index_, "].specific.harvest.curveRouter")), (address));

        int128 indexIn_ =
            abi.decode(json_.parseRaw(string.concat(".configs[", index_, "].specific.harvest.indexIn")), (int128));

        //Construct CurveSwap structs
        CurveSwap[] memory swaps_ = _getCurveSwaps(json_, index_);

        // Set harvest values
        ConvexCompounder(strategy).setHarvestValues(curveRouter_, swaps_, indexIn_);
    }

    function _getCurveSwaps(string memory json_, string memory index_) internal pure returns (CurveSwap[] memory) {
        uint256 swapLen = json_.readUint(string.concat(".configs[", index_, "].specific.harvest.swaps.length"));

        CurveSwap[] memory swaps_ = new CurveSwap[](swapLen);
        for (uint256 i; i < swapLen; i++) {
            // Read route and convert dynamic into fixed size array
            address[] memory route_ = json_.readAddressArray(
                string.concat(".configs[", index_, "].specific.harvest.swaps.structs[", vm.toString(i), "].route")
            );
            address[11] memory route;
            for (uint256 n; n < 11; n++) {
                route[n] = route_[n];
            }

            // Read swapParams and convert dynamic into fixed size array
            uint256[5][5] memory swapParams;
            for (uint256 n = 0; n < 5; n++) {
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
                for (uint256 y; y < 5; y++) {
                    swapParams[n][y] = swapParams_[y];
                }
            }

            // Read pools and convert dynamic into fixed size array
            address[] memory pools_ = json_.readAddressArray(
                string.concat(".configs[", index_, "].specific.harvest.swaps.structs[", vm.toString(i), "].pools")
            );
            address[5] memory pools;
            for (uint256 n = 0; n < 5; n++) {
                pools[n] = pools_[n];
            }

            // Construct the struct
            swaps_[i] = CurveSwap({route: route, swapParams: swapParams, pools: pools});
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
                                HARVEST
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public override {
        _mintAssetAndApproveForStrategy(10000e18, bob);
        vm.prank(bob);
        strategy.deposit(10000e18, bob);
        uint256 oldTa = strategy.totalAssets();

        vm.roll(block.number + 10000);
        vm.warp(block.timestamp + 150000);

        strategy.harvest(abi.encode(uint256(0)));

        assertGt(strategy.totalAssets(), oldTa);
    }

    function testFail__harvest_slippage_too_high() public {
        _mintAssetAndApproveForStrategy(10000e18, bob);
        vm.prank(bob);
        strategy.deposit(10000e18, bob);
        uint256 oldTa = strategy.totalAssets();

        vm.roll(block.number + 10000);
        vm.warp(block.timestamp + 150000);

        strategy.harvest(abi.encode(uint256(9621364723006598847)));

        assertGt(strategy.totalAssets(), oldTa);
    }

    function testFail__harvest_no_rewards() public {
        _mintAssetAndApproveForStrategy(100e18, bob);

        vm.prank(bob);
        strategy.deposit(100e18, bob);

        uint256 oldTa = strategy.totalAssets();

        strategy.harvest(abi.encode(uint256(10e18)));

        assertEq(strategy.totalAssets(), oldTa);
    }
}
