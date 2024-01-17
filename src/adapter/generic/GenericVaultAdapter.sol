// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {BaseAdapter, IERC20, IERC4626, AdapterConfig} from "../../base/BaseAdapter.sol";
import {IPermissionRegistry} from "../../base/interfaces/IPermissionRegistry.sol";

contract GenericVaultAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    IERC4626 public vault;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error NotEndorsed(address vault);
    error InvalidAsset();
    error LpTokenNotSupported();

    function __GenericVaultAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();

        __BaseAdapter_init(_adapterConfig);
        address _vault = abi.decode(_adapterConfig.protocolData, (address));

        // @dev permissionRegistry of eth
        // @dev change the registry address depending on the deployed chain
        if (
            !IPermissionRegistry(0x7a33b5b57C8b235A3519e6C010027c5cebB15CB4)
                .endorsed(_vault)
        ) revert NotEndorsed(_vault);
        if (IERC4626(_vault).asset() != address(_adapterConfig.underlying))
            revert InvalidAsset();

        vault = IERC4626(_vault);

        _adapterConfig.underlying.approve(_vault, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        return vault.previewRedeem(vault.balanceOf(address(this)));
    }

    function _totalLP() internal pure override returns (uint) {
        revert("NO");
    }

    function maxDeposit() public view override returns (uint256) {
        return paused() ? 0 : vault.maxDeposit(address(this));
    }

    function maxWithdraw() public view override returns (uint256) {
        return paused() ? underlying.balanceOf(address(this)) : vault.maxWithdraw(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        if (caller != address(this))
            underlying.safeTransferFrom(caller, address(this), amount);
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        vault.deposit(amount, address(this));
    }

    function _depositLP(uint) internal pure override {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 amount, address receiver) internal override {
        if (!paused()) _withdrawUnderlying(amount);
        underlying.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        vault.withdraw(amount, address(this), address(this));
    }

    function _withdrawLP(uint) internal pure override {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    function _claim() internal override {}
}
