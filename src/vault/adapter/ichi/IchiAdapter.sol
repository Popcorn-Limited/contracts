// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {IVault, IVaultFactory, IDepositGuard} from "./IIchi.sol";
import {UniswapV3Utils, IUniV3Pool} from "../../../utils/UniswapV3Utils.sol";
import {TickMath} from "src/interfaces/external/uni/v3/TickMath.sol";

/**
 * @title   Ichi Adapter
 * @author  amatureApe
 * @notice  ERC4626 wrapper for Ichi Vaults.
 *
 * An ERC4626 compliant Wrapper for
 * Allows wrapping Ichi Vaults.
 */
contract IchiAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    // /// @notice Ichi token
    // address public ichi;

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

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    /**
     * @notice Initialize a new MasterChef Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev `_pid` - The poolId for lpToken.
     * @dev `_rewardsToken` - The token rewarded by the Ichi contract
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory ichiInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        (
            uint256 _pid,
            address _depositGuard,
            address _vaultDeployer,
            address _uniRouter,
            uint24 _uniSwapFee,
            uint256 _slippage
        ) = abi.decode(
                ichiInitData,
                (uint256, address, address, address, uint24, uint256)
            );

        // if (!IPermissionRegistry(registry).endorsed(_gauge))
        //     revert NotEndorsed(_gauge);

        pid = _pid;
        vaultDeployer = _vaultDeployer;
        uniRouter = _uniRouter;
        uniSwapFee = _uniSwapFee;

        slippage = _slippage;

        depositGuard = IDepositGuard(_depositGuard);
        vaultFactory = IVaultFactory(depositGuard.ICHIVaultFactory());
        vault = IVault(vaultFactory.allVaults(pid));
        uniPool = IUniV3Pool(vault.pool());
        token0 = vault.token0();
        token1 = vault.token1();

        if (token0 != address(asset()) && token1 != address(asset()))
            revert InvalidAsset();

        assetIndex = token0 == address(asset()) ? 0 : 1;

        _name = string.concat(
            "VaultCraft Ichi ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcIchi-", IERC20Metadata(asset()).symbol());

        IERC20(assetIndex == 0 ? token0 : token1).approve(
            address(depositGuard),
            type(uint256).max
        );
        IERC20(assetIndex == 0 ? token1 : token0).approve(
            address(uniRouter),
            type(uint256).max
        );
    }

    function name()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _name;
    }

    function symbol()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.

    function _totalAssets() internal view override returns (uint256) {
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

        uint256 tempAssets = assetPairAmount + oppositePairInAssetPairTerms;

        return tempAssets - tempAssets.mulDiv(slippage, 1e18, Math.Rounding.Up);
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
        uint256 assets,
        uint256 shares
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    vault.balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
    }

    // function previewWithdraw(
    //     uint256 assets
    // ) public view override returns (uint256) {
    //     return
    //         _convertToShares(
    //             assets + assets.mulDiv(slippage, 1e18, Math.Rounding.Up),
    //             Math.Rounding.Up
    //         );
    // }

    // function previewRedeem(
    //     uint256 shares
    // ) public view override returns (uint256) {
    //     uint256 assets = _convertToAssets(shares, Math.Rounding.Down);
    //     return assets - assets.mulDiv(slippage, 1e18, Math.Rounding.Up);
    // }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/
    error OverMaxDeposit(uint256 amount, uint256 max);

    function _protocolDeposit(uint256 amount, uint256) internal override {
        uint256 depositMax = assetIndex == 0
            ? vault.deposit0Max()
            : vault.deposit1Max();

        if (amount > depositMax) revert OverMaxDeposit(amount, depositMax);

        depositGuard.forwardDepositToICHIVault(
            address(vault),
            address(vaultDeployer),
            address(asset()),
            amount,
            0,
            address(this)
        );
    }

    function _protocolWithdraw(
        uint256 amount,
        uint256 shares
    ) internal override {
        uint256 ichiShares = convertToUnderlyingShares(0, shares);

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
                address(asset()),
                uniSwapFee,
                oppositePairAmount
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice The token rewarded
    function rewardTokens()
        external
        view
        override
        returns (address[] memory _rewardTokens)
    {
        _rewardTokens = new address[](1);
        _rewardTokens[0] = address(0);
    }

    /*//////////////////////////////////////////////////////////////
                      EIP-165 LOGIC
  //////////////////////////////////////////////////////////////*/

    function supportsInterface(
        bytes4 interfaceId
    ) public pure override(WithRewards, AdapterBase) returns (bool) {
        return
            interfaceId == type(IWithRewards).interfaceId ||
            interfaceId == type(IAdapter).interfaceId;
    }
}
