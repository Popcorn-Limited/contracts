// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import "./IGmdVault.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract GmdAdapter is BaseAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 public poolId;
    IGmdVault public constant gmdVault = IGmdVault(0x8080B5cE6dfb49a6B86370d6982B3e2A86FBBb08);
    IERC20 public receiptToken;

    error LpTokenSupported();
    error InvalidPool(uint poolId);
    error InsufficientSharesReceived();
    error AssetMismatch(uint poolId, address asset, address lpToken);

    function __GmdAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (!_adapterConfig.useLpToken) revert LpTokenSupported();
        __BaseAdapter_init(_adapterConfig);

        poolId = abi.decode(_adapterConfig.protocolData, (uint256));

        IGmdVault.PoolInfo memory poolInfo = gmdVault.poolInfo(poolId);
        receiptToken = IERC20(poolInfo.GDlptoken);

        if (
            !poolInfo.stakable ||
            !poolInfo.rewardStart ||
            !poolInfo.withdrawable
        ) revert InvalidPool(poolId);
        if (address(lpToken) != poolInfo.lpToken)
            revert AssetMismatch(poolId, address(lpToken), poolInfo.lpToken);

        _adapterConfig.lpToken.approve(address(gmdVault), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of lptoken assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert
     * lpToken balance into lpToken balance
     */
    function _totalLP() internal view override returns (uint256) {
        IGmdVault.PoolInfo memory poolInfo = gmdVault.poolInfo(poolId);
        uint256 gmdLpTokenBalance = IERC20(poolInfo.GDlptoken).balanceOf(
            address(this)
        );
        uint256 asset = gmdLpTokenBalance.mulDiv(
            poolInfo.totalStaked,
            IERC20(poolInfo.GDlptoken).totalSupply(),
            Math.Rounding.Down
        );
        return asset.mulDiv(1e6, 1e18, Math.Rounding.Down);
    }

    function _totalUnderlying() internal pure override returns (uint) {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        lpToken.safeTransferFrom(caller, address(this), amount);
        _depositLP(amount);
    }

    function _depositUnderlying(uint) internal pure override {
        revert("NO");
    }

    /**
     * @notice Deposits lpToken asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overridden. Some farms require the user to into an lpToken before
     * depositing others might use the lpToken directly
     **/
    function _depositLP(uint256 amount) internal override {
        IERC20 receiptToken_ = receiptToken;
        uint256 initialReceiptTokenBalance = receiptToken_.balanceOf(
            address(this)
        );

        gmdVault.enter(amount, poolId);
        uint256 sharesReceived = receiptToken_.balanceOf(address(this)) -
            initialReceiptTokenBalance;
        if (sharesReceived <= 0) revert InsufficientSharesReceived();
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/
    function _withdraw(uint256 amount, address receiver) internal override {
        if (!paused()) _withdrawLP(amount);
        underlying.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws lpToken asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overridden. Some farms require the user to into an lpToken before depositing others
     * might use the underlying directly
     **/
    function _withdrawLP(uint256 amount) internal override {
        gmdVault.leave(convertToUnderlyingShares(amount), poolId);
    }

    function _withdrawUnderlying(uint) internal pure override {
        revert("NO");
    }

    function convertToUnderlyingShares(
        uint256 shares
    ) public view returns (uint256) {
        IGmdVault.PoolInfo memory poolInfo = gmdVault.poolInfo(poolId);
        uint256 supply = _totalLP();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    IERC20(poolInfo.GDlptoken).balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
    }

    function _claim() internal override {}
}
