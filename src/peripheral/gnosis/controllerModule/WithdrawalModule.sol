// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

import {ControllerModule, ModuleCall, ISafe} from "src/peripheral/gnosis/controllerModule/MainControllerModule.sol";
import {RequestBalance} from "src/vaults/multisig/phase1/BaseControlledAsyncRedeem.sol";
import {Owned} from "src/utils/Owned.sol";
import {TakeOverSafeLib} from "src/peripheral/gnosis/controllerModule/TakeOverSafeLib.sol";

interface IRequestableBalance {
    function requestBalances(
        address shareController
    ) external view returns (RequestBalance memory);
}

contract WithdrawalModule is Owned {
    IRequestableBalance public vault;
    ControllerModule public controller;

    address[] public newOwners;
    uint256 public newThreshold;

    constructor(
        address vault_,
        address controller_,
        address owner_
    ) Owned(owner_) {
        vault = IRequestableBalance(vault_);
        controller = ControllerModule(controller_);
    }

    /*//////////////////////////////////////////////////////////////
                        EXECUTION LOGIC
    //////////////////////////////////////////////////////////////*/

    function handoverSafeAfterIgnoredWithdrawal(
        address shareController
    ) external {
        RequestBalance memory requestBalance = vault.requestBalances(
            shareController
        );

        if (block.timestamp <= requestBalance.requestTime) revert("No timeout");

        TakeOverSafeLib.takeoverSafe(
            address(controller),
            newOwners,
            newThreshold
        );
    }
}
