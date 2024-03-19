// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.15;
import { MultiCall } from "../../IGearboxV3.sol";

library YearnV2 {
    function deposit(address strategyAdapter, uint256 amount) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeWithSignature("deposit(uint256)", amount)
        });
    }

    function deposit(address strategyAdapter, uint256 amount, address) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeWithSignature("deposit(uint256,address)", amount, address(0))
        });
    }

    function withdraw(address strategyAdapter, uint256 maxShares) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeWithSignature("withdraw(uint256)", maxShares)
        });
    }

    function withdraw(address strategyAdapter, uint256 maxShares, address) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeWithSignature("withdraw(uint256,address)", maxShares, address(0))
        });
    }
}
