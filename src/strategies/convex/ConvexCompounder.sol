// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../BaseStrategy.sol";
import {IConvexBooster, IConvexRewards, IRewards} from "./IConvex.sol";
import {ICurveLp, IGauge, ICurveRouter, CurveSwap, IMinter} from "../curve/ICurve.sol";

/**
 * @title   Convex Compounder Adapter
 * @author  ADiNenno
 * @notice  ERC4626 wrapper for Convex Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/convex-eth/platform/blob/main/contracts/contracts/Booster.sol.
 * Allows wrapping Convex Vaults with or without an active convexBooster.
 * Compounds rewards into the vault underlying.
 */
contract ConvexCompounder is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The poolId inside Convex booster for relevant Curve lpToken.
    uint256 public pid;

    uint256 internal nCoins;

    /// @notice The booster address for Convex
    IConvexBooster public convexBooster;

    /// @notice The Convex convexRewards.
    IConvexRewards public convexRewards;

    ICurveLp public pool;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error AssetMismatch();

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoDeposit_ Controls if `protocolDeposit` gets called on deposit
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function initialize(
        address asset_,
        address owner_,
        bool autoDeposit_,
        bytes memory strategyInitData_
    ) external initializer {
        (address _convexBooster, address _curvePool, uint256 _pid) = abi.decode(
            strategyInitData_,
            (address, address, uint256)
        );

        (, , , address _convexRewards, , ) = IConvexBooster(_convexBooster)
            .poolInfo(_pid);

        convexBooster = IConvexBooster(_convexBooster);
        convexRewards = IConvexRewards(_convexRewards);
        pid = _pid;
        nCoins = ICurveLp(_curvePool).N_COINS();
        pool = ICurveLp(_curvePool);

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(asset_).approve(_convexBooster, type(uint256).max);

        _name = string.concat(
            "VaultCraft Convex ",
            IERC20Metadata(asset_).name(),
            " Adapter"
        );
        _symbol = string.concat("vcCvx-", IERC20Metadata(asset_).symbol());
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
        return convexRewards.balanceOf(address(this));
    }

    /// @notice The token rewarded from the convex reward contract
    function rewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into Convex convexBooster contract.
    function _protocolDeposit(
        uint256 assets,
        uint256,
        bytes memory
    ) internal override {
        convexBooster.deposit(pid, assets, true);
    }

    /// @notice Withdraw from Convex convexRewards contract.
    function _protocolWithdraw(uint256 assets, uint256) internal override {
        /**
         * @dev No need to convert as Convex shares are 1:1 with Curve deposits.
         * @param assets Amount of shares to withdraw.
         * @param claim Claim rewards on withdraw?
         */
        convexRewards.withdrawAndUnwrap(assets, false);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    error CompoundFailed();

    /// @notice Claim liquidity mining rewards given that it's active
    function claim() internal override returns (bool success) {
        try convexRewards.getReward(address(this), true) {
            success = true;
        } catch {}
    }

    /**
     * @notice Claim rewards and compound them into the vault
     */
    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        claim();

        ICurveRouter router_ = curveRouter;
        uint256 amount;
        uint256 rewLen = _rewardTokens.length;
        for (uint256 i = 0; i < rewLen; i++) {
            address rewardToken = _rewardTokens[i];
            amount = IERC20(rewardToken).balanceOf(address(this));

            if (amount > 0) {
                CurveSwap memory swap = swaps[rewardToken];
                router_.exchange(
                    swap.route,
                    swap.swapParams,
                    amount,
                    0,
                    swap.pools
                );
            }
        }

        amount = IERC20(depositAsset).balanceOf(address(this));
        if (amount > 0) {
            uint256[] memory amounts = new uint256[](nCoins);
            amounts[uint256(uint128(indexIn))] = amount;

            ICurveLp(pool).add_liquidity(amounts, 0);

            uint256 minOut = abi.decode(data, (uint256));

            amount = IERC20(asset()).balanceOf(address(this));
            if (amount < minOut) revert CompoundFailed();

            _protocolDeposit(amount, 0, bytes(""));
        }

        emit Harvested();
    }

    address[] internal _rewardTokens;

    ICurveRouter public curveRouter;

    mapping(address => CurveSwap) internal swaps; // to swap reward token to baseAsset

    address public depositAsset;
    int128 public indexIn;

    error InvalidHarvestValues();

    function setHarvestValues(
        address curveRouter_,
        address[] memory rewardTokens_,
        CurveSwap[] memory swaps_, // must be ordered like rewardTokens_
        int128 indexIn_
    ) public onlyOwner {
        curveRouter = ICurveRouter(curveRouter_);

        _approveSwapTokens(rewardTokens_, curveRouter_);
        for (uint256 i = 0; i < rewardTokens_.length; i++) {
            swaps[rewardTokens_[i]] = swaps_[i];
        }

        address asset_ = asset();
        address depositAsset_ = ICurveLp(asset_).coins(
            uint256(uint128(indexIn_))
        );
        if (depositAsset != address(0)) IERC20(depositAsset).approve(asset_, 0);
        IERC20(depositAsset_).approve(asset_, type(uint256).max);

        depositAsset = depositAsset_;
        indexIn = indexIn_;

        _rewardTokens = rewardTokens_;
    }

    function _approveSwapTokens(
        address[] memory rewardTokens_,
        address curveRouter_
    ) internal {
        uint256 rewardTokenLen = _rewardTokens.length;
        if (rewardTokenLen > 0) {
            // void approvals
            for (uint256 i = 0; i < rewardTokenLen; i++) {
                IERC20(_rewardTokens[i]).approve(curveRouter_, 0);
            }
        }

        for (uint256 i = 0; i < rewardTokens_.length; i++) {
            IERC20(rewardTokens_[i]).approve(curveRouter_, type(uint256).max);
        }
    }
}
