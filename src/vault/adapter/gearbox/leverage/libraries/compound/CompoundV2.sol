// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.15;
import { MultiCall } from "../../IGearboxV3.sol";
import { ICompoundV2_CTokenAdapter } from "../IAdapter.sol";

library CompoundV2 {
    function mint(address strategyAdapter, uint256 mintAmount) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(ICompoundV2_CTokenAdapter.mint, (mintAmount))
        });
    }

    function redeem(address strategyAdapter, uint256 redeemTokens) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(ICompoundV2_CTokenAdapter.redeem, (redeemTokens))
        });
    }
}
