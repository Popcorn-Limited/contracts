// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.25;

import {MultiCall} from "../IGearboxV3.sol";
import {IwstETHV1Adapter} from "../IGearboxStrategyAdapter.sol";
import {GearboxLeverageFarm} from "../GearboxLeverageFarm.sol";

contract GearboxLeverageFarmWstETHV1 is GearboxLeverageFarm {
    function _gearboxStrategyDeposit(bytes memory data) internal override {
        (uint256 amount) = abi.decode(data, (uint256));

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({target: strategyAdapter, callData: abi.encodeCall(IwstETHV1Adapter.wrap, (amount))});

        creditFacade.multicall(creditAccount, calls);
    }

    function _gearboxStrategyWithdraw(bytes memory data) internal override {
        (uint256 amount) = abi.decode(data, (uint256));

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({target: strategyAdapter, callData: abi.encodeCall(IwstETHV1Adapter.unwrap, (amount))});

        creditFacade.multicall(creditAccount, calls);
    }
}