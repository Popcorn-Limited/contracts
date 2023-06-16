// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {IVault, IVaultFactory, IDepositGuard} from "./IIchi.sol";
import {UniswapV3Utils} from "../../../utils/UniswapV3Utils.sol";

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

    /// @notice Uniswap Price Quoter
    address public uniQuoter;

    /// @notice Uniswap alternate token -> asset swapfee
    uint24 public uniSwapFee;

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
            address _uniQuoter,
            uint24 _uniSwapFee
        ) = abi.decode(
                ichiInitData,
                (uint256, address, address, address, address, uint24)
            );

        // if (!IPermissionRegistry(registry).endorsed(_gauge))
        //     revert NotEndorsed(_gauge);

        pid = _pid;
        vaultDeployer = _vaultDeployer;
        uniRouter = _uniRouter;
        uniQuoter = _uniQuoter;
        uniSwapFee = _uniSwapFee;

        depositGuard = IDepositGuard(_depositGuard);
        vaultFactory = IVaultFactory(depositGuard.ICHIVaultFactory());
        vault = IVault(vaultFactory.allVaults(pid));
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

        (uint256 tokenShareA, uint256 tokenShareB) = calculateUnderlyingShare(
            lpTokenBalance,
            totalSupply,
            underlyingTokenSupplyA,
            underlyingTokenSupplyB
        );

        address assetPair = assetIndex == 0 ? token0 : token1;
        uint256 assetPairAmount = assetIndex == 0 ? tokenShareA : tokenShareB;

        address oppositePair = assetIndex == 0 ? token1 : token0;
        uint256 oppositePairAmount = assetIndex == 0
            ? tokenShareB
            : tokenShareA;

        uint256 oppositePairCurrentSwapPrice = UniswapV3Utils
            .quoteExactSinglePrice(
                uniQuoter,
                oppositePair,
                assetPair,
                oppositePairAmount,
                uniSwapFee,
                0
            );

        return assetPairAmount + oppositePairCurrentSwapPrice;
    }

    function calculateUnderlyingShare(
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

    function _protocolWithdraw(uint256 amount, uint256) internal override {
        (uint256 amount0, uint256 amount1) = vault.withdraw(
            amount,
            address(this)
        );

        address oppositePair = assetIndex == 0 ? token1 : token0;
        uint256 oppositePairAmount = assetIndex == 0 ? amount1 : amount0;

        UniswapV3Utils.swap(
            uniRouter,
            oppositePair,
            address(asset()),
            uniSwapFee,
            oppositePairAmount
        );
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
