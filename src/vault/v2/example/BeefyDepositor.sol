// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BeefyAdapter, IERC20} from "./BeefyAdapter.sol";

contract BeefyDepositor is BeefyAdapter {
    function initialize(
        IERC20 _underlying,
        IERC20 _lpToken,
        bool _useLpToken,
        IERC20[] memory _rewardTokens,
        address _registry,
        bytes memory _beefyInitData
    ) external onlyInitializing {
        __BeefyAdapter_init(
            _underlying,
            _lpToken,
            _useLpToken,
            _rewardTokens,
            _registry,
            _beefyInitData
        );
    }

    function deposit(uint256 amount) external override onlyVault whenNotPaused {
        _deposit(amount);
    }

    function withdraw(uint256 amount) external override onlyVault {
        _withdraw(amount);
    }
}
