// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.12 <0.9.0;

import {Owned} from "src/utils/Owned.sol";

enum Operation {
    Call,
    DelegateCall
}

interface ISafe {
    function getOwners() external view returns (address[] memory);

    function getThreshold() external view returns (uint256);

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Operation operation
    ) external returns (bool success);
}

interface IOwnerManager {
    function removeOwner(
        address prevOwner,
        address owner,
        uint256 _threshold
    ) external;
    function swapOwner(
        address prevOwner,
        address oldOwner,
        address newOwner
    ) external;
    function addOwnerWithThreshold(address owner, uint256 _threshold) external;
    function changeThreshold(uint256 _threshold) external;
}

/// @title Social Recovery Module
/// @author CANDIDE Labs
contract ControllerModule is Owned {
    address internal constant SENTINEL_OWNERS = address(0x1);

    address public gnosisSafe;

    constructor(address gnosisSafe_, address owner_) Owned(owner_) {
        gnosisSafe = gnosisSafe_;
    }

    /**
     * @notice Finalizes an ongoing recovery request if the recovery period is over.
     * The method is public and callable by anyone to enable orchestration.
     */
    function overtakeSafe(
        address[] memory newOwners,
        uint256 newThreshold
    ) external onlyOwner {
        address _gnosisSafe = gnosisSafe;
        ISafe safe = ISafe(_gnosisSafe);
        address[] memory owners = safe.getOwners();

        // remove owners
        for (uint256 i = (owners.length - 1); i > 0; --i) {
            bool success = safe.execTransactionFromModule({
                to: _gnosisSafe,
                value: 0,
                data: abi.encodeCall(
                    IOwnerManager.removeOwner,
                    (owners[i - 1], owners[i], 1)
                ),
                operation: Operation.Call
            });
            if (!success) {
                revert("SM: owner removal failed");
            }
        }

        for (uint256 i = 0; i < newOwners.length; i++) {
            bool success;
            if (i == 0) {
                if (newOwners[i] == owners[i]) continue;
                success = safe.execTransactionFromModule({
                    to: _gnosisSafe,
                    value: 0,
                    data: abi.encodeCall(
                        IOwnerManager.swapOwner,
                        (SENTINEL_OWNERS, owners[i], newOwners[i])
                    ),
                    operation: Operation.Call
                });
                if (!success) {
                    revert("SM: owner replacement failed");
                }
                continue;
            }
            success = safe.execTransactionFromModule({
                to: _gnosisSafe,
                value: 0,
                data: abi.encodeCall(
                    IOwnerManager.addOwnerWithThreshold,
                    (newOwners[i], 1)
                ),
                operation: Operation.Call
            });
            if (!success) {
                revert("SM: owner addition failed");
            }
        }

        if (newThreshold > 1) {
            bool success = safe.execTransactionFromModule({
                to: _gnosisSafe,
                value: 0,
                data: abi.encodeCall(
                    IOwnerManager.changeThreshold,
                    (newThreshold)
                ),
                operation: Operation.Call
            });
            if (!success) {
                revert("SM: change threshold failed");
            }
        }
    }
}
