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
    IERC20 public receiptToken;

    error MaxLossTooHigh();
    error NoSharesBurned();
    error InvalidPool(uint poolId);
    error InsufficientSharesReceived();
    error AssetMismatch(uint poolId, address asset, address lpToken);

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory gmdInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        _name = string.concat(
            "VaultCraft GMD ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );

        _symbol = string.concat("vcGMD-", IERC20Metadata(asset()).symbol());

        poolId = abi.decode(gmdInitData, (uint256));
        gmdVault = IGmdVault(registry);

        IGmdVault.PoolInfo memory poolInfo = gmdVault.poolInfo(poolId);
        receiptToken = IERC20(poolInfo.GDlptoken);

        if (
            !poolInfo.stakable ||
            !poolInfo.rewardStart ||
            !poolInfo.withdrawable
        ) revert InvalidPool(poolId);

        if(asset() != poolInfo.lpToken)
            revert AssetMismatch(poolId, asset(), poolInfo.lpToken);

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
        uint256 gmdLpTokenBalance = IERC20(poolInfo.GDlptoken).balanceOf(address(this));
        uint256 gmdLpTokenTotalSupply = IERC20(poolInfo.GDlptoken).totalSupply();
        uint256 asset = gmdLpTokenBalance.mulDiv(
            poolInfo.totalStaked,
            gmdLpTokenTotalSupply,
             Math.Rounding.Floor
        );
        return asset.mulDiv(1e6, 1e18,  Math.Rounding.Floor); //scaled down the value since
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LIMIT LOGIC
  //////////////////////////////////////////////////////////////*/

    /// @notice Applies the yVault deposit limit to the adapter.
    function maxDeposit(address) public view override returns (uint256) {
        if (paused()) return 0;

        IGmdVault.PoolInfo memory poolInfo = gmdVault.poolInfo(poolId);

        if (poolInfo.totalStaked >= poolInfo.vaultcap) return 0;
        return poolInfo.vaultcap - poolInfo.totalStaked;
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
                 Math.Rounding.Ceil
            );
    }

    /// @notice Deposit into beefy vault and optionally into the booster given its configured
    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        IGmdVault.PoolInfo memory poolInfo = gmdVault.poolInfo(poolId);
        IERC20 receiptToken_ = receiptToken;

        uint256 initialReceiptTokenBalance = receiptToken_.balanceOf(address(this));

        gmdVault.enter(amount, poolId);
        uint256 sharesReceived = receiptToken_.balanceOf(address(this)) - initialReceiptTokenBalance;
        if(sharesReceived <= 0) revert InsufficientSharesReceived();
    }

    /// @notice Withdraw from the beefy vault and optionally from the booster given its configured
    function _protocolWithdraw(
        uint256,
        uint256 shares
    ) internal virtual override {
        if(shares <= 0) revert NoSharesBurned();
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
