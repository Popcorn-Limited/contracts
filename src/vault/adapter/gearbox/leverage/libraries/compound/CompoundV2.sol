// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.17;

import {ICompoundV2_CTokenAdapter} from "../../../interfaces/compound/ICompoundV2_CTokenAdapter.sol";

library CompoundV2 {
    function mint(address protocolAdapter, uint256 mintAmount) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: protocolAdapter,
            callData: abi.encodeCall(ICompoundV2_CTokenAdapter.mint, (mintAmount))
        });
    }

    function redeem(address protocolAdapter, uint256 redeemTokens) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: protocolAdapter,
            callData: abi.encodeCall(ICompoundV2_CTokenAdapter.redeem, (redeemTokens))
        });
    }
}
