// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../BaseStrategy.sol";
import {IConvexBooster, IConvexRewards} from "./IConvex.sol";
import {BaseCurveLpCompounder, CurveSwap, ICurveLp} from "../../peripheral/BaseCurveLpCompounder.sol";

/**
 * @title   Convex Compounder Adapter
 * @author  ADiNenno
 * @notice  ERC4626 wrapper for Convex Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/convex-eth/platform/blob/main/contracts/contracts/Booster.sol.
 * Allows wrapping Convex Vaults with or without an active convexBooster.
 * Compounds rewards into the vault underlying.
 */
contract ConvexCompounder is BaseStrategy, BaseCurveLpCompounder {
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
    function initialize(address asset_, address owner_, bool autoDeposit_, bytes memory strategyInitData_)
        external
        initializer
    {
        (address _convexBooster, address _curvePool, uint256 _pid) =
            abi.decode(strategyInitData_, (address, address, uint256));

        (,,, address _convexRewards,,) = IConvexBooster(_convexBooster).poolInfo(_pid);

        convexBooster = IConvexBooster(_convexBooster);
        convexRewards = IConvexRewards(_convexRewards);
        pid = _pid;
        nCoins = ICurveLp(_curvePool).N_COINS();
        pool = ICurveLp(_curvePool);

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(asset_).approve(_convexBooster, type(uint256).max);

        _name = string.concat("VaultCraft Convex ", IERC20Metadata(asset_).name(), " Adapter");
        _symbol = string.concat("vcCvx-", IERC20Metadata(asset_).symbol());
    }

    function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _name;
    }

    function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
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
    function _protocolDeposit(uint256 assets, uint256, bytes memory) internal override {
        convexBooster.deposit(pid, assets, true);
    }

    /// @notice Withdraw from Convex convexRewards contract.
    function _protocolWithdraw(uint256 assets, uint256, bytes memory) internal override {
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

        sellRewardsViaCurve();

        sellRewardsForLpTokenViaCurve(address(pool), asset(), nCoins, data);

        _protocolDeposit(IERC20(asset()).balanceOf(address(this)), 0, bytes(""));

        emit Harvested();
    }

    function setHarvestValues(address newRouter, CurveSwap[] memory newSwaps, int128 indexIn_) external onlyOwner {
        setCurveLpCompounderValues(newRouter, newSwaps, address(pool), indexIn_);
    }
}
