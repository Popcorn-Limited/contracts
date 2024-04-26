// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.25;
import { MultiCall } from "../IGearboxV3.sol";
import { GearboxLeverageFarm } from "../GearboxLeverageFarm.sol";

contract GearboxLeverageFarmCurveV1 is GearboxLeverageFarm{

    function _gearboxStrategyDeposit(bytes memory data) internal override {
        (uint256 amount, uint256 i, uint256 minAmount) = abi.decode(data, (uint256, uint256, uint256));
        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeWithSignature("add_liquidity_one_coin(uint256,uint256,uint256)", amount, i, minAmount)
        });

        creditFacade.multicall(creditAccount, calls);
    }

    function _gearboxStrategyWithdraw(bytes memory data) internal override {
        (uint256 token_amount, int128 i, uint256 min_amount) = abi.decode(data, (uint256, int128, uint256));
        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeWithSignature(
                "remove_liquidity_one_coin(uint256,int128,uint256)", token_amount, i, min_amount
            )
        });

        creditFacade.multicall(creditAccount, calls);
    }
}
