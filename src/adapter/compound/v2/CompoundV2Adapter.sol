// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../../base/BaseAdapter.sol";
import {ICToken, IComptroller} from "./ICompoundV2.sol";
import {LibCompound} from "./LibCompound.sol";

contract CompoundV2Adapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The Compound cToken contract
    ICToken public cToken;

    /// @notice The Compound Comptroller contract
    IComptroller public comptroller;

    /// @notice Check to see if cToken is cETH to wrap/unwarp on deposit/withdrawal
    bool public isCETH;

    error InvalidAsset(address asset);

    error DifferentAssets(address asset, address underlying);

    function __CompoundV2Adapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        __BaseAdapter_init(_adapterConfig);

        (address _cToken, address _comptroller) = abi.decode(
            _protocolConfig.protocolInitData,
            (address, address)
        );

        cToken = ICToken(_cToken);
        comptroller = IComptroller(_comptroller);

        if (
            keccak256(abi.encode(cToken.symbol())) !=
            keccak256(abi.encode("cETH"))
        ) {
            if (cToken.underlying() != address(_adapterConfig.underlying))
                revert DifferentAssets(
                    cToken.underlying(),
                    address(_adapterConfig.underlying)
                );
        }

        (bool isListed, , ) = comptroller.markets(address(cToken));
        if (isListed == false) revert InvalidAsset(address(cToken));

        _adapterConfig.underlying.approve(address(cToken), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overridden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        return LibCompound.viewUnderlyingBalanceOf(cToken, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        underlying.safeTransferFrom(caller, address(this), amount);
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        cToken.mint(amount);
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
        cToken.redeemUnderlying(amount);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        try comptroller.claimComp(address(this)) {} catch {}
    }
}
