// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.15;
import { MultiCall } from "../../IGearboxV3.sol";
import { GearboxLeverage } from "../../GearboxLeverage.sol";
import {
    ICreditFacadeV3Multicall
} from "../../IGearboxV3.sol";

contract GearboxLeverage_CurveV1 is GearboxLeverage {

    function _gearboxStrategyDeposit(bytes memory data) internal override {
        (uint256 amount, uint256 i, uint256 minAmount) = abi.decode(data, (uint256, uint256, uint256));

        MultiCall[] memory calls = new MultiCall[](2);

        // request lp price update
        // calls[0] = MultiCall({
        //     target: address(creditFacade),
        //     callData: abi.encodeCall(ICreditFacadeV3Multicall.onDemandPriceUpdate, (address(0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72), false, hex""))
        // });

        // // strategy adapter to approve curve router
        // calls[1] = MultiCall({
        //     target: strategyAdapter,
        //     callData: abi.encodeWithSignature("approve(uint256,uint256,uint256)", amount, i, minAmount)
        // });

        uint256[2] memory amounts = [0, amount];

        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeWithSignature("add_liquidity(uint256[2],uint256)", amounts, minAmount)
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
