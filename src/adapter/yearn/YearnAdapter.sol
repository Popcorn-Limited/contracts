// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;
import {VaultAPI, IYearnRegistry} from "./IYearn.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract YearnAdapter is BaseAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;

    VaultAPI public yVault;
    
    uint256 public maxLoss;

    IYearnRegistry public constant YEARN_REGISTRY =
        IYearnRegistry(0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804);

    uint256 constant DEGRADATION_COEFFICIENT = 10 ** 18;

    error MaxLossTooHigh();
    error LpTokenNotSupported();

    function __YearnAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();
        __BaseAdapter_init(_adapterConfig);

        maxLoss = abi.decode(_adapterConfig.protocolData, (uint256));
        yVault = VaultAPI(YEARN_REGISTRY.latestVault(address(underlying)));

        if (maxLoss > 10_000) revert MaxLossTooHigh();
        _adapterConfig.underlying.approve(address(yVault), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        return _shareValue(yVault.balanceOf(address(this)));
    }

    function _totalLP() internal pure override returns (uint) {
        revert("NO");
    }

    /// @notice Determines the current value of `yShares` in assets
    function _shareValue(uint256 yShares) internal view returns (uint256) {
        if (yVault.totalSupply() == 0) return yShares;

        return
            yShares.mulDiv(
                _freeFunds(),
                yVault.totalSupply(),
                Math.Rounding.Down
            );
    }

    /// @notice The amount of assets that are free to be withdrawn from the yVault after locked profts.
    function _freeFunds() internal view returns (uint256) {
        return _yTotalAssets() - _calculateLockedProfit();
    }

    /**
     * @notice Returns the total quantity of all assets under control of this Vault,
     * whether they're loaned out to a Strategy, or currently held in the Vault.
     */
    function _yTotalAssets() internal view virtual returns (uint256) {
        return underlying.balanceOf(address(yVault)) + yVault.totalDebt();
    }

    /// @notice Calculates how much profit is locked and cant be withdrawn.
    function _calculateLockedProfit() internal view returns (uint256) {
        uint256 lockedFundsRatio = (block.timestamp - yVault.lastReport()) *
            yVault.lockedProfitDegradation();

        if (lockedFundsRatio < DEGRADATION_COEFFICIENT) {
            uint256 lockedProfit = yVault.lockedProfit();
            return
                lockedProfit -
                ((lockedFundsRatio * lockedProfit) / DEGRADATION_COEFFICIENT);
        } else {
            return 0;
        }
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
        yVault.deposit(amount);
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
        yVault.withdraw(
            convertToUnderlyingShares(amount),
            address(this),
            maxLoss
        );
    }

    function _withdrawLP(uint) internal pure override {
        revert("NO");
    }

    /// @notice The amount of aave shares to withdraw given an mount of adapter shares
    function convertToUnderlyingShares(
        uint256 shares
    ) public view returns (uint256) {
        uint256 supply = _totalUnderlying();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    yVault.balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
    }

    function _claim() internal override {}

    /*//////////////////////////////////////////////////////////////
                            MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    event MaxLossChanged(uint256 oldMaxLoss, uint256 newMaxLoss);

    function setMaxLoss(uint256 _maxLoss) external {
        if (_maxLoss > 10_000) revert MaxLossTooHigh();
        emit MaxLossChanged(maxLoss, _maxLoss);
        maxLoss = _maxLoss;
    }
}
