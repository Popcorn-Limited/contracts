// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.17;

import {MultiCall} from "@gearbox-protocol/core-v2/contracts/libraries/MultiCall.sol";


library YearnV2 {
    function deposit(address protocolAdapter, uint256 amount) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: protocolAdapter, 
            callData: abi.encodeWithSignature("deposit(uint256)", amount)
        });
    }

    function deposit(address protocolAdapter, uint256 amount, address) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: protocolAdapter,
            callData: abi.encodeWithSignature("deposit(uint256,address)", amount, address(0))
        });
    }

    function withdraw(address protocolAdapter, uint256 maxShares) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: protocolAdapter, 
            callData: abi.encodeWithSignature("withdraw(uint256)", maxShares)
        });
    }

    function withdraw(address protocolAdapter, uint256 maxShares, address) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: protocolAdapter,
            callData: abi.encodeWithSignature("withdraw(uint256,address)", maxShares, address(0))
        });
    }
}
