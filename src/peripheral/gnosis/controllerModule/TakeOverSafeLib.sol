// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

import {ControllerModule, ModuleCall, ISafe, Enum} from "src/peripheral/gnosis/controllerModule/MainControllerModule.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "src/utils/Owned.sol";
import {OwnerManager} from "safe-smart-account/base/OwnerManager.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

library TakeOverSafeLib {
    function takeoverSafe(
        address controller,
        address[] memory newOwners_,
        uint256 newThreshold_
    ) internal {
        address gnosisSafe = ControllerModule(controller).gnosisSafe();
        ISafe safe = ISafe(gnosisSafe);
        address[] memory owners = safe.getOwners();

        // remove owners
        for (uint256 i = (owners.length - 1); i > 0; --i) {
            bool success = safe.execTransactionFromModule({
                to: gnosisSafe,
                value: 0,
                data: abi.encodeCall(
                    OwnerManager.removeOwner,
                    (owners[i - 1], owners[i], 1)
                ),
                operation: Enum.Operation.Call
            });
            if (!success) {
                revert("SM: owner removal failed");
            }
        }

        for (uint256 i = 0; i < newOwners_.length; i++) {
            bool success;
            if (i == 0) {
                if (newOwners_[i] == owners[i]) continue;
                success = safe.execTransactionFromModule({
                    to: gnosisSafe,
                    value: 0,
                    data: abi.encodeCall(
                        OwnerManager.swapOwner,
                        (address(0x1), owners[i], newOwners_[i])
                    ),
                    operation: Enum.Operation.Call
                });
                if (!success) {
                    revert("SM: owner replacement failed");
                }
                continue;
            }
            success = safe.execTransactionFromModule({
                to: gnosisSafe,
                value: 0,
                data: abi.encodeCall(
                    OwnerManager.addOwnerWithThreshold,
                    (newOwners_[i], 1)
                ),
                operation: Enum.Operation.Call
            });
            if (!success) {
                revert("SM: owner addition failed");
            }
        }

        if (newThreshold_ > 1) {
            bool success = safe.execTransactionFromModule({
                to: gnosisSafe,
                value: 0,
                data: abi.encodeCall(
                    OwnerManager.changeThreshold,
                    (newThreshold_)
                ),
                operation: Enum.Operation.Call
            });
            if (!success) {
                revert("SM: change threshold failed");
            }
        }
    }
}
