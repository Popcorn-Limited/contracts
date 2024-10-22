// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @notice Gas optimized Pausable for smart contracts.
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Pausable.sol)
abstract contract Pausable {
    bool public paused;

    event Paused(address account);
    event Unpaused(address account);

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function _requireNotPaused() internal view virtual {
        if (paused) {
            revert("Pausable/paused");
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused) {
            revert("Pausable/not-paused");
        }
    }

    function _pause() internal virtual whenNotPaused {
        paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal virtual whenPaused {
        paused = false;
        emit Unpaused(msg.sender);
    }
}
