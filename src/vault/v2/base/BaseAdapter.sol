// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {OwnedUpgradeable} from "../../../utils/OwnedUpgradeable.sol";

import {IBaseStrategy} from "./interfaces/IBaseStrategy.sol";

abstract contract BaseAdapter is OwnedUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public underlying;
    IERC20 public lpToken;

    bool public useLpToken;

    mapping(address => bool) public isVault;

    IERC20[] public rewardTokens;

    modifier onlyVault() {
        require(isVault[msg.sender], "Only vault");
        _;
    }

    // TODO Add pausing
    // TODO Who can call which functions? (who is Owner?)
    // TODO move performance fees into vaults or adapter?

    function __BaseAdapter_init(
        IERC20 _underlying,
        IERC20 _lpToken,
        bool _useLpToken,
        IERC20[] memory _rewardTokens
    ) internal {
        __Owned_init(msg.sender);

        underlying = _underlying;
        lpToken = _lpToken;
        useLpToken = _useLpToken;
        rewardTokens = _rewardTokens;
    }

    /**
     * @notice Deposit Asset into the wrapped farm
     * @dev Uses either `_depositUnderlying` or `_depositLP`
     * @dev Only callable by the vault
     **/
    function deposit(uint256 amount) external virtual onlyVault {
        if (IBaseStrategy(address(this)).autoHarvest())
            IBaseStrategy(address(this))._harvest(
                IBaseStrategy(address(this)).harvestData()
            );

        // TODO could we move this check into the vault and combine meta and none meta strategies?
        if (useLpToken) {
            lpToken.safeTransferFrom(msg.sender, address(this), amount);
            _depositLP(amount);
        } else {
            underlying.safeTransferFrom(msg.sender, address(this), amount);
            _depositUnderlying(amount);
        }
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
        if (IBaseStrategy(address(this)).autoHarvest())
            IBaseStrategy(address(this))._harvest(
                IBaseStrategy(address(this)).harvestData()
            );
        if (useLpToken) {
            _withdrawLP(amount);
            lpToken.safeTransfer(msg.sender, amount);
        } else {
            _withdrawUnderlying(amount);
            underlying.safeTransfer(msg.sender, amount);
        }
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
     * @notice Claims rewards
     */
    function _claimRewards() internal virtual {}

    /// @dev This function needs to be called by a trusted contract on initialization of a new vault that wants to use this strategy
    function addVault(address _vault) external onlyOwner {
        isVault[_vault] = true;
    }

    /// @dev RewardTokens get set manually instead of fetched to allow the trusted party to ignore certain rewards if they choose to
    /// @dev This function should be called by a trusted strategist / the DAO
    function setRewardsToken(IERC20[] memory _rewardTokens) external onlyOwner {
        rewardTokens = _rewardTokens;
    }
}
