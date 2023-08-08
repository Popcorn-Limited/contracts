// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract BaseAdapter {
    IERC20 public underlying;
    IERC20 public lpToken;
    address public vault;
    bool public useLpToken;

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    function initialize() internal initializer {}

    /**
     * @notice Deposit Asset into the wrapped farm
     * @dev Uses either `_depositUnderlying` or `_depositLP`
     * @dev Only callable by the vault
     **/
    function deposit(uint256 amount) external virtual onlyVault {
        useLpToken ? _depositLP(amount) : _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal virtual {}

    /**
     * @notice Deposits the lpToken directly into the farm
     * @dev This function is optional. Some farms might require the user to deposit lpTokens directly into the farm
     **/
    function _depositLP(uint256 amount) internal virtual {}

    /**
     * @notice Withdraws Asset from the wrapped farm
     * @dev Uses either `_withdrawUnderlying` or `_withdrawLP`
     * @dev Only callable by the vault
     **/
    function withdraw(uint256 amount) external virtual onlyVault {
        useLpToken ? _withdrawLP(amount) : _withdrawUnderlying(amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal virtual {}

    /**
     * @notice Withdraws the lpToken directly from the farm
     * @dev This function is optional. Some farms might require the user to deposit lpTokens directly into the farm
     **/
    function _withdrawLP(uint256 amount) internal virtual {}

    /**
     * @notice Returns the total amount of assets
     */
    function totalAssets() external view virtual returns (uint256) {
        return useLpToken ? _totalLP() : _totalUnderlying();
    }

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view virtual returns (uint256) {}

    /**
     * @notice Returns the total amount of lpToken
     * @dev This function is optional. Some farms might require the user to deposit lpTokens directly into the farm
     */
    function _totalLP() internal view virtual returns (uint256) {}

    /**
     * @notice Returns the strategy’s reward tokens
     */
    function rewardToken() external view virtual returns (address[] memory) {}

    /**
     * @notice Claims rewards & executes the strategy
     */
    function harvest(bytes optionalData) external view virtual {}

    /**
     * @notice Claims rewards
     */
    function _claim() internal virtual {}
}
