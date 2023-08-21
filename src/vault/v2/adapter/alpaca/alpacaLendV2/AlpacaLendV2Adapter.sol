// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IAlpacaLendV2Vault, IAlpacaLendV2Manger, IAlpacaLendV2MiniFL, IAlpacaLendV2IbToken} from "./IAlpacaLendV2.sol";


contract AlpacaLendV1Adapter is BaseAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice The Alpaca Lend V2 Manager contract
    IAlpacaLendV2Manger public alpacaManager;

    /// @notice The Alpaca Lend V2 MiniFL contract
    IAlpacaLendV2MiniFL public miniFL;

    /// @notice The Alpaca Lend V2 ibToken
    IAlpacaLendV2IbToken public ibToken;

    /// @notice PoolId corresponding to collateral in Alpaca Manger
    uint256 public pid;

    error InvalidAsset();

    function __AlpacaLendV2Adapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        __BaseAdapter_init(_adapterConfig);

        uint256 _pid = abi.decode(_protocolConfig.protocolInitData, (uint256));

        alpacaManager = IAlpacaLendV2Manger(_protocolConfig.registry);
        miniFL = IAlpacaLendV2MiniFL(alpacaManager.miniFL());

        ibToken = IAlpacaLendV2IbToken(miniFL.stakingTokens(_pid));

        if (ibToken.asset() != address(underlying)) revert InvalidAsset();

        pid = _pid;
        _adapterConfig.underlying.approve(address(alpacaManager), type(uint256).max);
        _adapterConfig.lpToken.approve(address(alpacaManager), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overridden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        uint256 assets = ibToken.convertToAssets(
            ibToken.balanceOf(address(this))
        );

        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount) internal override {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        alpacaManager.deposit(address(underlying), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 amount, address receiver) internal override {
        _withdrawUnderlying(amount);
        underlying.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        uint256 alpacaShares = ibToken.convertToShares(amount);
        alpacaManager.withdraw(address(ibToken), alpacaShares);
    }
}
