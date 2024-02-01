// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../../../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../../../abstracts/WithRewards.sol";
import {ICurveLp, IGauge, ICurveRouter, CurveSwap} from "./IArbCurve.sol";

/**
 * @title   Curve Child Gauge Adapter
 * @notice  ERC4626 wrapper for  Curve Child Gauge Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/curvefi/curve-xchain-factory/blob/master/contracts/implementations/ChildGauge.vy.
 * Allows wrapping Curve Child Gauge Vaults.
 */
contract CurveGaugeSingleAssetCompounder is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    address public lpToken;
    IGauge public gauge;
    int128 internal indexIn;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    function initialize(
        bytes memory adapterInitData,
        address,
        bytes memory curveInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        (address _lpToken, address _gauge, int128 _indexIn) = abi.decode(
            curveInitData,
            (address, address, int128)
        );

        lpToken = _lpToken;
        gauge = IGauge(_gauge);
        indexIn = _indexIn;

        _name = string.concat(
            "VaultCraft CurveGauge ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcCrvG-", IERC20Metadata(asset()).symbol());

        IERC20(_lpToken).approve(_gauge, type(uint256).max);
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
        uint256 lpBal = IERC20(address(gauge)).balanceOf(address(this));
        return
            lpBal > 0
                ? ICurveLp(lpToken).calc_withdraw_one_coin(lpBal, indexIn)
                : 0;
    }

    /// @notice The token rewarded from the convex reward contract
    function rewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    /**
     * @notice Simulate the effects of a deposit at the current block, given current on-chain conditions.
     * @dev Return 0 if paused since no further deposits are allowed.
     * @dev Override this function if the underlying protocol has a unique deposit logic and/or deposit fees.
     */
    function previewDeposit(
        uint256 assets
    ) public view virtual override returns (uint256) {
        return paused() ? 0 : _convertToShares(assets, Math.Rounding.Down);
    }

    /**
     * @notice Simulate the effects of a mint at the current block, given current on-chain conditions.
     * @dev Return 0 if paused since no further deposits are allowed.
     * @dev Override this function if the underlying protocol has a unique deposit logic and/or deposit fees.
     */
    function previewMint(
        uint256 shares
    ) public view virtual override returns (uint256) {
        return paused() ? 0 : _convertToAssets(shares, Math.Rounding.Up);
    }

    /** @dev See {IERC4626-previewWithdraw}. */
    function previewWithdraw(
        uint256 assets
    ) public view virtual override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Up);
    }

    /** @dev See {IERC4626-previewRedeem}. */
    function previewRedeem(
        uint256 shares
    ) public view virtual override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    // TODO override max views

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 amount, uint256) internal override {
        //_exchange(curveRouter, swaps[asset()], amount);
        IERC20(asset()).approve(lpToken, amount);

        uint256[] memory amounts = new uint256[](2);
        amounts[1] = amount;
        ICurveLp(lpToken).add_liquidity(amounts, 0);
        gauge.deposit(IERC20(lpToken).balanceOf(address(this)));
    }

    event log_named_uint(string, uint256);

    function _protocolWithdraw(
        uint256 assets,
        uint256 shares
    ) internal override {
        uint256 lpBal = IERC20(address(gauge)).balanceOf(address(this));

        uint256 lpWithdraw = shares.mulDiv(
            lpBal,
            totalSupply(),
            Math.Rounding.Up
        );
        emit log_named_uint("assets", assets);
        emit log_named_uint("shares", shares);

        emit log_named_uint("lpBal", lpBal);
        emit log_named_uint("lpWithdraw", lpWithdraw);

        gauge.withdraw(lpWithdraw);
        // _exchange(
        //     curveRouter,
        //     swaps[lpToken],
        //     IERC20(lpToken).balanceOf(address(this))
        // );
        ICurveLp(lpToken).remove_liquidity_one_coin(lpWithdraw, indexIn, 0);
        uint256 assetBal = IERC20(asset()).balanceOf(address(this));
        emit log_named_uint("assetBal", assetBal);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    address[] internal _rewardTokens;
    uint256[] public minTradeAmounts; // ordered as in rewardsTokens()

    ICurveRouter public curveRouter;

    address[] public swapTokens;
    mapping(address => CurveSwap) internal swaps; // to swap reward token to baseAsset

    error InvalidHarvestValues();

    function getSwapTokens() external view returns (address[] memory) {
        return swapTokens;
    }

    function getRoute(address key) external view returns (address[11] memory) {
        return swaps[key].route;
    }

    function getSwapParams(
        address key
    ) external view returns (uint256[5][5] memory) {
        return swaps[key].swapParams;
    }

    function setHarvestValues(
        address curveRouter_,
        address[] memory rewardTokens_,
        uint256[] memory minTradeAmounts_, // must be ordered like rewardTokens_
        address[] memory swapTokens_, // must be ordered to have rewardTokens as the first addresses ordered like in rewardTokens_ ([...rewardTokens_, rest])
        CurveSwap[] memory swaps_ // must be ordered like swapTokens_
    ) public onlyOwner {
        curveRouter = ICurveRouter(curveRouter_);

        _rewardTokens = rewardTokens_;
        minTradeAmounts = minTradeAmounts_;

        _approveSwapTokens(swapTokens_, curveRouter_);
        swapTokens = swapTokens_;
        for (uint256 i = 0; i < swapTokens_.length; i++) {
            swaps[swapTokens_[i]] = swaps_[i];
        }
    }

    function _approveSwapTokens(
        address[] memory swapTokens_,
        address curveRouter_
    ) internal {
        uint256 swapTokensLen = swapTokens.length;
        if (swapTokensLen > 0) {
            // void approvals
            for (uint256 i = 0; i < swapTokensLen; i++) {
                IERC20(swapTokens[i]).approve(curveRouter_, 0);
            }
        }

        for (uint256 i = 0; i < swapTokens_.length; i++) {
            IERC20(swapTokens_[i]).approve(curveRouter_, type(uint256).max);
        }
    }

    /**
     * @notice Claim rewards and compound them into the vault
     */
    function harvest() public override takeFees {
        if ((lastHarvest + harvestCooldown) < block.timestamp) {
            claim();

            ICurveRouter router_ = curveRouter;
            uint256 amount;
            uint256 rewLen = _rewardTokens.length;
            for (uint256 i = 0; i < rewLen; i++) {
                address rewardToken = _rewardTokens[i];
                if (rewardToken == swapTokens[i]) {
                    amount = IERC20(rewardToken).balanceOf(address(this));
                    if (amount > minTradeAmounts[i])
                        _exchange(router_, swaps[rewardToken], amount);
                }
            }

            uint256 depositAmount = IERC20(asset()).balanceOf(address(this));
            if (depositAmount > 0) _protocolDeposit(depositAmount, 0);

            //gauge.deposit(IERC20(lpToken).balanceOf(address(this)));

            lastHarvest = block.timestamp;
        }

        emit Harvested();
    }

    function _exchange(
        ICurveRouter router,
        CurveSwap memory swap,
        uint256 amount
    ) internal {
        if (amount == 0) revert ZeroAmount();
        router.exchange(swap.route, swap.swapParams, amount, 0, swap.pools);
    }

    /// @notice Claim rewards from the gauge
    function claim() public override returns (bool success) {
        try gauge.claim_rewards() {
            success = true;
        } catch {}
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
