// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;
import "./lib.sol";
import {IAmmPoolsService, IAmmPoolsLens} from "./IIPorProtocol.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {IPermissionRegistry} from "../../../interfaces/vault/IPermissionRegistry.sol";

enum PoolAsset {
    DAI,
    USDC,
    USDT
}

/**
 * @title   Ipor Adapter
 * @author  mayorcoded
 * @notice  ERC4626 wrapper for Ipor Vaults.
 *
 * An ERC4626 compliant Wrapper for
 * https://github.com/IPOR-Labs/ipor-protocol/blob/main/contracts/interfaces/IAmmPoolsService.sol.
 * Allows wrapping Ipor amm pool service by providing liquidity to the pool and earning revenue Ipor's
 * asset management system
 */
contract IporAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice Ipor Amm Pool service contract
    IAmmPoolsService public ammPoolsService;

    /// @notice Ipor Amm Pool service contract Lens
    IAmmPoolsLens public ammPoolsLens;

    /// @notice IpToken for Amm Pool service contract
    IIpToken public ipToken;

    /// @notice enum to choose pool function
    PoolAsset internal poolAsset;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    error NotEndorsed(address _contract);
    error AssetNotSupport(address asset);

    /**
     * @notice Initialize a new Radiant Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param iporInitData Encoded data for the Ipor adapter initialization.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory iporInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);
        address _asset = asset();

        (address _ammPoolService, address _ammPoolsLens) = abi.decode(
            iporInitData,
            (address, address)
        );
        if (!IPermissionRegistry(registry).endorsed(_ammPoolService))
            revert NotEndorsed(_ammPoolService);
        if (!IPermissionRegistry(registry).endorsed(_ammPoolsLens))
            revert NotEndorsed(_ammPoolsLens);

        ammPoolsService = IAmmPoolsService(_ammPoolService);
        ammPoolsLens = IAmmPoolsLens(_ammPoolsLens);

        IAmmPoolsService.AmmPoolsServicePoolConfiguration
            memory poolConfig = IAmmPoolsService(_ammPoolService)
                .getAmmPoolServiceConfiguration(_asset);
        ipToken = IIpToken(poolConfig.ipToken);

        if (_asset == LibIpor.DAI) {
            poolAsset = PoolAsset.DAI;
        } else if (_asset == LibIpor.USDC) {
            poolAsset = PoolAsset.USDC;
        } else if (_asset == LibIpor.USDT) {
            poolAsset = PoolAsset.USDT;
        } else {
            revert AssetNotSupport(_asset);
        }

        _name = string.concat(
            "VaultCraft Ipor ",
            IERC20Metadata(_asset).name(),
            " Adapter"
        );
        _symbol = string.concat("vcIpor-", IERC20Metadata(_asset).symbol());
        IERC20(_asset).approve(_ammPoolService, type(uint256).max);
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

    function _totalAssets() internal view override returns (uint256) {
        return
            LibIpor.viewUnderlyingBalanceOf(
                ipToken,
                ammPoolsLens,
                asset(),
                address(this)
            );
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into aave lending pool
    function _protocolDeposit(
        uint256 assets,
        uint256
    ) internal virtual override {
        if (poolAsset == PoolAsset.DAI) {
            ammPoolsService.provideLiquidityDai(address(this), assets);
        } else if (poolAsset == PoolAsset.USDC) {
            ammPoolsService.provideLiquidityUsdc(address(this), assets);
        } else if (poolAsset == PoolAsset.USDT) {
            ammPoolsService.provideLiquidityUsdt(address(this), assets);
        }
    }

    /// @notice Withdraw from lending pool
    function _protocolWithdraw(
        uint256 assets,
        uint256
    ) internal virtual override {
        if (poolAsset == PoolAsset.DAI) {
            ammPoolsService.redeemFromAmmPoolDai(address(this), assets);
        } else if (poolAsset == PoolAsset.USDC) {
            ammPoolsService.redeemFromAmmPoolUsdc(address(this), assets);
        } else if (poolAsset == PoolAsset.USDT) {
            ammPoolsService.redeemFromAmmPoolUsdt(address(this), assets);
        }
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
