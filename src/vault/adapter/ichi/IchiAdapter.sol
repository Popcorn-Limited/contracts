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

    /// @notice Ichi token
    address public ichi;

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
    uint8 public assetIndex;

    /// @notice Uniswap Router
    address public uniRouter;

    /// @notice Uniswap Ichi -> asset swapfee
    uint24 public swapFee;

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
            uint24 _swapFee
        ) = abi.decode(
                ichiInitData,
                (uint256, address, address, address, uint24)
            );

        // if (!IPermissionRegistry(registry).endorsed(_gauge))
        //     revert NotEndorsed(_gauge);

        pid = _pid;
        vaultDeployer = _vaultDeployer;
        uniRouter = _uniRouter;
        swapFee = _swapFee;

        depositGuard = IDepositGuard(_depositGuard);
        vaultFactory = IVaultFactory(depositGuard.ICHIVaultFactory());
        vault = IVault(vaultFactory.allVaults(pid));

        if (vault.token0() != asset() && vault.token1() != asset())
            revert InvalidAsset();

        assetIndex = vault.token0() == address(asset()) ? 0 : 1;
        ichi = assetIndex == 0 ? vault.token0() : vault.token1();

        _name = string.concat(
            "VaultCraft Ichi ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcIchi-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).approve(address(depositGuard), type(uint256).max);
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
        (uint256 amount0, uint256 amount1) = vault.getTotalAmounts();

        // uint256 underlyingAmount0 = Math.mulDiv(
        //     vault.balanceOf(address(this)),
        //     amount0,
        //     totalSupply()
        // );
        // uint256 underlyingAmount1 = Math.mulDiv(
        //     vault.balanceOf(address(this)),
        //     amount1,
        //     totalSupply()
        // );

        // uint256 amountAsset = assetIndex == 0
        //     ? underlyingAmount0
        //     : underlyingAmount1;

        // uint256 ichiAmount = assetIndex == 0
        //     ? underlyingAmount1
        //     : underlyingAmount0;

        // uint256 totalAssets = amountAsset + ichiAmount;

        return vault.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 amount, uint256) internal override {
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

        uint256 ichiAmount = assetIndex == 0 ? amount1 : amount0;

        UniswapV3Utils.swap(
            uniRouter,
            ichi,
            address(asset()),
            swapFee,
            ichiAmount
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
