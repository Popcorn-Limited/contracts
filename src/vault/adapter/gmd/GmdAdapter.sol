// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./IGmdVault.sol";
import { AdapterBase, IERC20, IERC20Metadata, ERC20, SafeERC20, Math, IAdapter} from "../abstracts/AdapterBase.sol";
import { WithRewards, IWithRewards } from "../abstracts/WithRewards.sol";


contract GmdAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    uint256 public poolId;
    IGmdVault public gmdVault;

    error InvalidPool(uint poolId);
    error AssetMismatch(uint poolId, address asset, address lpToken);

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory gmdInitData
    ) external initializer {

        _name = string.concat(
            "VaultCraft GMD ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcGMD-", IERC20Metadata(asset()).symbol());

        poolId = abi.decode(gmdInitData, (uint256));
        gmdVault = IGmdVault(registry);

        IGmdVault.PoolInfo memory poolInfo = gmdVault.poolInfo(poolId);

        if (
            !poolInfo.stakable ||
            !poolInfo.rewardStart ||
            !poolInfo.withdrawable
        ) revert InvalidPool(poolId);

        (address _asset,,,,,) = abi.decode(
            adapterInitData,
            (address, address, address, uint256, bytes4[8], bytes)
        );
        if(_asset != poolInfo.lpToken)
            revert AssetMismatch(poolId, _asset, poolInfo.lpToken);

        __AdapterBase_init(adapterInitData);
        IERC20(asset()).approve(address(gmdVault), type(uint256).max);
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
        IGmdVault.PoolInfo memory poolInfo = gmdVault.poolInfo(poolId);
        return IERC20(poolInfo.GDlptoken).balanceOf(address(this)) * gmdVault.GDpriceToStakedtoken(poolId);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/
    function convertToUnderlyingShares(
        uint256 assets,
        uint256 shares
    ) public view override returns (uint256) {
        IGmdVault.PoolInfo memory poolInfo = gmdVault.poolInfo(poolId);
        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                IERC20(poolInfo.GDlptoken).balanceOf(address(this)),
                supply,
                Math.Rounding.Up
            );
    }

    /// @notice Deposit into beefy vault and optionally into the booster given its configured
    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        gmdVault.enter(amount, poolId);
    }

    /// @notice Withdraw from the beefy vault and optionally from the booster given its configured
    function _protocolWithdraw(
        uint256,
        uint256 shares
    ) internal virtual override {
        uint256 gmdVaultShares = convertToUnderlyingShares(0, shares);
        gmdVault.leave(gmdVaultShares, poolId);
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
