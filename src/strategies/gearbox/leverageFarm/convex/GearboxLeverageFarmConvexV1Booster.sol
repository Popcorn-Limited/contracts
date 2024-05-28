// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.25;

import {MultiCall} from "../IGearboxV3.sol";
import {IConvexV1BoosterAdapter} from "../IGearboxStrategyAdapter.sol";
import {GearboxLeverageFarm} from "../GearboxLeverageFarm.sol";

contract GearboxLeverageFarmConvexV1Booster is GearboxLeverageFarm {
    function _gearboxStrategyDeposit(bytes memory data) internal override {
        (uint256 pid, uint256 amount, bool stake) = abi.decode(data, (uint256, uint256, bool));
        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IConvexV1BoosterAdapter.deposit, (pid, amount, stake))
        });
        creditFacade.multicall(creditAccount, calls);
    }

    function _gearboxStrategyWithdraw(bytes memory data) internal override {
        (uint256 pid, uint256 amount) = abi.decode(data, (uint256, uint256));
        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IConvexV1BoosterAdapter.withdraw, (pid, amount))
        });
        creditFacade.multicall(creditAccount, calls);
    }
}
