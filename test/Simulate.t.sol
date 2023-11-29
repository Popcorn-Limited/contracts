// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {MockERC20} from "./utils/mocks/MockERC20.sol";
import {IMultiRewardEscrow} from "../src/interfaces/IMultiRewardEscrow.sol";
import {MultiRewardStaking, IERC20} from "../src/utils/MultiRewardStaking.sol";
import {MultiRewardEscrow} from "../src/utils/MultiRewardEscrow.sol";

contract SimulateTest is Test {
    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);
    }

    function test_all_the_things() public {
        // Activate TokenAdmin
        tokenAdmin.activate();

        // Add gauges
        controller.add_type("Ethereum", 1);
        address[] memory vaults = [
            0x759281a408A48bfe2029D259c23D7E848A7EA1bC,
            0x6cE9c05E159F8C4910490D8e8F7a63e95E6CEcAF
        ];
        gauges = new ILiquidityGauge[](vaults.length);
        for (uint256 i; i < vaults.length; ) {
            gauges[i] = ILiquidityGauge(factory.create(vaults[i], 1e18));

            controller.add_gauge(address(gauges[i]), 0, 1);

            gauges[i].set_tokenless_production(20);

            unchecked {
                ++i;
            }
        }

        // Lock VCX_LP
        deal(address(VCX_LP), admin, 1e18);
    }
}
