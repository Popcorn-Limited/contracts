// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.25;
import { MultiCall } from "../../IGearboxV3.sol";
import { ILidoV1Adapter } from "../IGearboxStrategyAdapter.sol";
import { GearboxLeverage } from "../../GearboxLeverage.sol";

contract GearboxLeverage_LidoV1 is GearboxLeverage {
    function _gearboxStrategyDeposit(bytes memory data) internal override {
        (uint256 amount) = abi.decode(data, (uint256));

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(ILidoV1Adapter.submit, (amount))
        });
        creditFacade.multicall(creditAccount, calls);
    }

    function _gearboxStrategyWithdraw(bytes memory data) internal override {

    }
}
