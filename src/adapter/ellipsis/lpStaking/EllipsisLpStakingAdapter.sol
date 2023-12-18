// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IEllipsis, ILpStaking, IAddressProvider} from "../IEllipsis.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../../base/BaseAdapter.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract EllipsisLpStakingAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @dev BSC address
    ILpStaking public constant lpStaking = ILpStaking(0x5B74C99AA2356B4eAa7B85dC486843eDff8Dfdbe);
    address[] internal _rewardToken;

    error InvalidToken();
    error LpTokenSupported();

    function __EllipsisLpStakingAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (!_adapterConfig.useLpToken) revert LpTokenSupported();

        __BaseAdapter_init(_adapterConfig);

        uint256 pId = abi.decode(_adapterConfig.protocolData, (uint256));

        if (lpStaking.registeredTokens(pId) != address(lpToken))
            revert InvalidToken();

        _adapterConfig.lpToken.approve(address(lpStaking), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalLP() internal view override returns (uint256) {
        return
            lpStaking.userInfo(address(lpToken), address(this)).depositAmount;
    }

    function _totalUnderlying() internal pure override returns (uint) {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        _depositLP(amount);
    }

    function _depositUnderlying(uint) internal pure override {
        revert("NO");
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositLP(uint256 amount) internal override {
        lpStaking.deposit(address(lpToken), amount, false);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 amount, address receiver) internal override {
        if (!paused()) _withdrawLP(amount);
        lpToken.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawLP(uint256 amount) internal override {
        lpStaking.withdraw(address(lpToken), amount, false);
    }

    function _withdrawUnderlying(uint) internal pure override {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        try lpStaking.claim(address(this), _rewardToken) {} catch {}
    }
}
