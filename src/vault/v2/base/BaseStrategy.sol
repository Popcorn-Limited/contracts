// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract BaseStrategy {
    bool public autoHarvest;
    bytes public harvestData;

    function __BaseStrategy_init(
        bool _autoHarvest,
        bytes memory _harvestData
    ) internal onlyInitializing {
        autoHarvest = _autoHarvest;
        harvestData = _harvestData;
    }

    // TODO how do we differentiate between strategy deposit and adapter deposit since we cant have two times the same base inheritance
    /**
     * @notice Deposit Asset into the wrapped farm
     * @dev Uses either `_depositUnderlying` or `_depositLP`
     * @dev Only callable by the vault
     **/
    function deposit(uint256 amount) external virtual override onlyVault {
        if (autoHarvest) _harvest(harvestData);
        useLpToken ? _depositLP(amount) : _depositUnderlying(amount);
    }

    // TODO how do we differentiate between strategy withdraw and adapter withdraw since we cant have two times the same base inheritance
    /**
     * @notice Withdraws Asset from the wrapped farm
     * @dev Uses either `_withdrawUnderlying` or `_withdrawLP`
     * @dev Only callable by the vault
     **/
    function withdraw(uint256 amount) external virtual override onlyVault {
        if (autoHarvest) _harvest(harvestData);
        useLpToken ? _withdrawLP(amount) : _withdrawUnderlying(amount);
    }

    /**
     * @notice Claims rewards & executes the strategy
     */
    function harvest(bytes optionalData) external view virtual {
        _harvest(optionalData);
    }

    /**
     * @notice Claims rewards & executes the strategy
     */
    function _harvest(bytes optionalData) internal view virtual {}
}
