// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.25;

import {MultiCall} from "../IGearboxV3.sol";
import {GearboxLeverageFarm} from "../GearboxLeverageFarm.sol";
import {ICompoundV2_CTokenAdapter} from "../IGearboxStrategyAdapter.sol";

contract GearboxLeverageFarmCompoundV2 is GearboxLeverageFarm {
    function _gearboxStrategyDeposit(bytes memory data) internal override {
        (uint256 mintAmount) = abi.decode(data, (uint256));

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] =
            MultiCall({target: strategyAdapter, callData: abi.encodeCall(ICompoundV2_CTokenAdapter.mint, (mintAmount))});
        creditFacade.multicall(creditAccount, calls);
    }

    function _gearboxStrategyWithdraw(bytes memory data) internal override {
        (uint256 redeemTokens) = abi.decode(data, (uint256));

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(ICompoundV2_CTokenAdapter.redeem, (redeemTokens))
        });
        creditFacade.multicall(creditAccount, calls);
    }
}