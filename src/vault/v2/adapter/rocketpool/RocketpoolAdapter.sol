// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {UniswapV3Utils, IUniV3Pool} from "../../../../utils/UniswapV3Utils.sol";
import {BaseAdapter, IERC20 as ERC20, AdapterConfig, ProtocolConfig} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {
    IWETH,
    ICurveMetapool,
    RocketStorageInterface,
    RocketTokenRETHInterface,
    RocketDepositPoolInterface,
    RocketDepositSettingsInterface,
    RocketNetworkBalancesInterface
} from "./IRocketpool.sol";

contract RocketpoolAdapter is BaseAdapter {
    using SafeERC20 for ERC20;
    using Math for uint256;

    address public uniRouter;
    uint24 public uniSwapFee;

    bytes32 public constant rocketDepositPoolKey =
        keccak256(abi.encodePacked("contract.address", "rocketDepositPool"));
    bytes32 public constant rETHKey =
        keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"));

    IWETH public WETH;
    RocketStorageInterface public rocketStorage;

    error NoSharesBurned();
    error InvalidAddress();
    error LpTokenNotSupported();
    error InsufficientSharesReceived();

    function __RocketpoolAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();
        __BaseAdapter_init(_adapterConfig);

        rocketStorage = RocketStorageInterface(_protocolConfig.registry); // TODO what are the security assumptions here? Where does this data come from?
        (address _weth, address _uniRouter, uint24 _uniSwapFee) = abi.decode(
            _protocolConfig.protocolInitData,
            (address, address, uint24)
        ); // TODO what are the security assumptions here? Where does this data come from?
        WETH = IWETH(_weth);
        uniRouter = _uniRouter;
        uniSwapFee = _uniSwapFee;

        address rocketDepositPoolAddress = rocketStorage.getAddress(
            rocketDepositPoolKey
        );
        address rETHAddress = rocketStorage.getAddress(rETHKey);

        if (rocketDepositPoolAddress == address(0) || rETHAddress == address(0))
            revert InvalidAddress();

        RocketTokenRETHInterface rETH = RocketTokenRETHInterface(rETHAddress);

        rETH.approve(uniRouter, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overridden. If the farm requires the usage of lpToken than this function
     * must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        RocketTokenRETHInterface rETH = _getRocketToken();
        return rETH.getEthValue(rETH.balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        underlying.safeTransferFrom(caller, address(this), amount); // TODO -- if caller is address(this) (from unpause) we shouldnt call this
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overridden. Some farms require the user to into an lpToken before depositing
     *      others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        WETH.withdraw(amount);
        _getDepositPool().deposit{value: amount}();
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
     * @dev This function must be overridden. Some farms require the user to into an lpToken before depositing
     * others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        RocketTokenRETHInterface rETH = _getRocketToken();
        uint256 rETHShares = rETH.getRethValue(amount) + 1;

        if (rETH.getTotalCollateral() > amount) {
            rETH.burn(rETHShares);
            WETH.deposit{value: amount}();
        } else {
            //if there isn't enough ETH in the rocket pool, we swap rETH directly for WETH
            UniswapV3Utils.swap(
                uniRouter,
                address(rETH),
                address(underlying),
                uniSwapFee,
                rETHShares
            );
        }
    }

    function convertToUnderlyingShares(
        uint256 shares
    ) public view returns (uint256) {
        uint256 supply = _totalUnderlying();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    _getRocketToken().balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/
    function _getDepositPool()
        internal
        view
        returns (RocketDepositPoolInterface)
    {
        return
            RocketDepositPoolInterface(
                rocketStorage.getAddress(rocketDepositPoolKey)
            );
    }

    function _getRocketToken()
        internal
        view
        returns (RocketTokenRETHInterface)
    {
        return RocketTokenRETHInterface(rocketStorage.getAddress(rETHKey));
    }
}