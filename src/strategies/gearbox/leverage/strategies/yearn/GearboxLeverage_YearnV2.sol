// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.25;
import { MultiCall } from "../../IGearboxV3.sol";
import { GearboxLeverage } from "../../GearboxLeverage.sol";

contract GearboxLeverage_YearnV2 is GearboxLeverage {
    function _gearboxStrategyDeposit(bytes memory data) internal override {
        (uint256 amount) = abi.decode(data, (uint256));

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeWithSignature("deposit(uint256)", amount)
        });

        creditFacade.multicall(creditAccount, calls);
    }

    function _gearboxStrategyWithdraw(bytes memory data) internal override {
        (uint256 maxShares) = abi.decode(data, (uint256));

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeWithSignature("withdraw(uint256)", maxShares)
        });
        creditFacade.multicall(creditAccount, calls);
    }
}
