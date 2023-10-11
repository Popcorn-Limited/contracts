// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IVault, IVaultFactory, IDepositGuard} from "./IIchi.sol";
import {TickMath} from "src/interfaces/external/uni/v3/TickMath.sol";
import {UniswapV3Utils, IUniV3Pool} from "../../../../utils/UniswapV3Utils.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig, IERC4626} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract IchiAdapter is BaseAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice The Ichi vault contract
    IVault public vault;

    /// @notice The Ichi Deposit Guard contract
    IDepositGuard public depositGuard;

    /// @notice The Ichi vault factory contract
    IVaultFactory public vaultFactory;

    /// @notice Vault Deployer contract
    address public vaultDeployer;

    /// @notice The pool ID
    uint256 public pid;

    /// @notice The index of the asset token within the pool
    uint256 public assetIndex;

    /// @notice Token0
    address public token0;

    /// @notice Token1
    address public token1;

    /// @notice Uniswap Router
    address public uniRouter;

    /// @notice Uniswap underlyin Pool
    IUniV3Pool public uniPool;

    /// @notice Uniswap alternate token -> asset swapfee
    uint24 public uniSwapFee;

    uint256 public slippage;

    error InvalidAsset();
    error LpTokenNotSupported();

    function __IchiAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();
        __BaseAdapter_init(_adapterConfig);

        (
            uint256 _pid,
            address _depositGuard,
            address _vaultDeployer,
            address _uniRouter,
            uint24 _uniSwapFee,
            uint256 _slippage
        ) = abi.decode(
            _protocolConfig.protocolInitData,
            (uint256, address, address, address, uint24, uint256)
        );

        pid = _pid;
        slippage = _slippage;
        uniRouter = _uniRouter;
        uniSwapFee = _uniSwapFee;
        vaultDeployer = _vaultDeployer;

        depositGuard = IDepositGuard(_depositGuard);
        vaultFactory = IVaultFactory(depositGuard.ICHIVaultFactory());
        vault = IVault(vaultFactory.allVaults(pid));
        uniPool = IUniV3Pool(vault.pool());
        token0 = vault.token0();
        token1 = vault.token1();

        if (token0 != address(underlying) && token1 != address(underlying))
            revert InvalidAsset();

        assetIndex = token0 == address(underlying) ? 0 : 1;

        IERC20(assetIndex == 0 ? token0 : token1).approve(
            address(depositGuard),
            type(uint256).max
        );
        IERC20(assetIndex == 0 ? token1 : token0).approve(
            address(uniRouter),
            type(uint256).max
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        uint256 lpTokenBalance = vault.balanceOf(address(this));
        uint256 totalSupply = vault.totalSupply();
        (uint256 underlyingTokenSupplyA, uint256 underlyingTokenSupplyB) = vault
            .getTotalAmounts();

        (uint256 tokenShareA, uint256 tokenShareB) = calculateUnderlyingShares(
            lpTokenBalance,
            totalSupply,
            underlyingTokenSupplyA,
            underlyingTokenSupplyB
        );

        uint256 assetPairAmount = assetIndex == 0 ? tokenShareA : tokenShareB;
        uint256 oppositePairAmount = assetIndex == 0
            ? tokenShareB
            : tokenShareA;

        int24 currentTick = vault.currentTick();
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(currentTick);
        uint256 priceRatio = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >>
                    192;

        if (assetIndex == 0) {
            priceRatio = (1 << 192) / priceRatio;
        }

        uint256 oppositePairInAssetPairTerms = oppositePairAmount * priceRatio;

        uint256 assets = assetPairAmount + oppositePairInAssetPairTerms;

        return assets - assets.mulDiv(slippage, 1e18, Math.Rounding.Up);
    }

    function calculateUnderlyingShares(
        uint256 lpTokenBalance,
        uint256 totalSupply,
        uint256 underlyingTokenSupplyA,
        uint256 underlyingTokenSupplyB
    ) public pure returns (uint256, uint256) {
        uint256 lpShare = lpTokenBalance * 1e18;
        uint256 lpShareFraction = lpShare / totalSupply;

        uint256 underlyingTokenShareA = (underlyingTokenSupplyA *
            lpShareFraction) / 1e18;
        uint256 underlyingTokenShareB = (underlyingTokenSupplyB *
            lpShareFraction) / 1e18;

        return (underlyingTokenShareA, underlyingTokenShareB);
    }

    function getSqrtPriceX96(
        int24 tick
    ) public pure returns (uint160 sqrtPriceX96) {
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        return sqrtPriceX96;
    }

    function convertToUnderlyingShares(
        uint256 shares
    ) public view returns (uint256) {
        uint256 supply = _totalUnderlying();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                vault.balanceOf(address(this)),
                supply,
                Math.Rounding.Up
            );
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/
    error OverMaxDeposit(uint256 amount, uint256 max);

    function _deposit(uint256 amount) internal override {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        uint256 depositMax = assetIndex == 0
            ? vault.deposit0Max()
            : vault.deposit1Max();

        if (amount > depositMax) revert OverMaxDeposit(amount, depositMax);

        depositGuard.forwardDepositToICHIVault(
            address(vault),
            address(vaultDeployer),
            address(underlying),
            amount,
            0,
            address(this)
        );
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
        uint256 ichiShares = convertToUnderlyingShares(amount);

        (uint256 amount0, uint256 amount1) = vault.withdraw(
            ichiShares,
            address(this)
        );

        address oppositePair = assetIndex == 0 ? token1 : token0;
        uint256 oppositePairAmount = assetIndex == 0 ? amount1 : amount0;

        if (oppositePairAmount > 0) {
            UniswapV3Utils.swap(
                uniRouter,
                oppositePair,
                address(underlying),
                uniSwapFee,
                oppositePairAmount
            );
        }
    }
}
