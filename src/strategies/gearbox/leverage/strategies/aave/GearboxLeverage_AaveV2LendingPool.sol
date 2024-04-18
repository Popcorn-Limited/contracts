// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.25;

import { MultiCall } from "../../IGearboxV3.sol";
import { GearboxLeverage } from "../../GearboxLeverage.sol";
import { IAaveV2_LendingPoolAdapter } from "../IGearboxStrategyAdapter.sol";

contract GearboxLeverage_AaveV2LendingPool is GearboxLeverage {
    function _gearboxStrategyDeposit(bytes memory data) internal override {
        (address asset, uint256 amount) = abi.decode(data, (address , uint256));

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IAaveV2_LendingPoolAdapter.deposit, (asset, amount, address(0), 0))
        });

        creditFacade.multicall(creditAccount, calls);
    }

    function _gearboxStrategyWithdraw(bytes memory data) internal override {
        (address asset, uint256 amount) = abi.decode(data, (address , uint256));

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IAaveV2_LendingPoolAdapter.withdraw, (asset, amount, address(0)))
        });

        creditFacade.multicall(creditAccount, calls);
    }
}
