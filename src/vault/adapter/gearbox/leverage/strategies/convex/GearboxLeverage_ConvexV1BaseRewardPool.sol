// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.15;
import { MultiCall } from "../../IGearboxV3.sol";
import { GearboxLeverage } from "../../GearboxLeverage.sol";
import { IConvexV1BaseRewardPoolAdapter } from "../IGearboxStrategyAdapter.sol";

contract GearboxLeverage_ConvexV1BaseRewardPool is GearboxLeverage {
    function _gearboxStrategyDeposit(bytes memory data) internal override {
        (uint256 amount) = abi.decode(data, (uint256));

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IConvexV1BaseRewardPoolAdapter.stake, (amount))
        });
        creditFacade.multicall(creditAccount, calls);
    }

    function _gearboxStrategyWithdraw(bytes memory data) internal override {
        (uint256 amount, bool claim) = abi.decode(data, (uint256, bool));
        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IConvexV1BaseRewardPoolAdapter.withdraw, (amount, claim))
        });
        creditFacade.multicall(creditAccount, calls);
    }
}
