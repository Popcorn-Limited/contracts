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
    uint256 internal nCoins;

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
        nCoins = ICurveLp(_lpToken).N_COINS();

        _name = string.concat(
            "VaultCraft CurveGaugeSingleAssetCompounder ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-sccrv-", IERC20Metadata(asset()).symbol());

        IERC20(_lpToken).approve(_gauge, type(uint256).max);
        IERC20(asset()).approve(_lpToken, type(uint256).max);
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

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 amount, uint256) internal override {
        uint256[] memory amounts = new uint256[](nCoins);
        amounts[uint256(uint128(indexIn))] = amount;

        ICurveLp(lpToken).add_liquidity(amounts, 0);
        gauge.deposit(IERC20(lpToken).balanceOf(address(this)));
    }

    function _protocolWithdraw(uint256, uint256 shares) internal override {
        uint256 lpWithdraw = shares.mulDiv(
            IERC20(address(gauge)).balanceOf(address(this)),
            totalSupply(),
            Math.Rounding.Up
        );

        gauge.withdraw(lpWithdraw);

        ICurveLp(lpToken).remove_liquidity_one_coin(lpWithdraw, indexIn, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    address[] internal _rewardTokens;
    uint256[] public minTradeAmounts; // ordered as in rewardsTokens()

    ICurveRouter public curveRouter;

    mapping(address => CurveSwap) internal swaps; // to swap reward token to baseAsset

    error InvalidHarvestValues();

    function setHarvestValues(
        address curveRouter_,
        address[] memory rewardTokens_,
        uint256[] memory minTradeAmounts_, // must be ordered like rewardTokens_
        CurveSwap[] memory swaps_ // must be ordered like rewardTokens_
    ) public onlyOwner {
        curveRouter = ICurveRouter(curveRouter_);

        _approveSwapTokens(rewardTokens_, curveRouter_);
        for (uint256 i = 0; i < rewardTokens_.length; i++) {
            swaps[rewardTokens_[i]] = swaps_[i];
        }

        _rewardTokens = rewardTokens_;
        minTradeAmounts = minTradeAmounts_;
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
                amount = IERC20(rewardToken).balanceOf(address(this));
                if (amount > minTradeAmounts[i]) {
                    _exchange(router_, swaps[rewardToken], amount);
                }
            }

            uint256 depositAmount = IERC20(asset()).balanceOf(address(this));
            if (depositAmount > 0) _protocolDeposit(depositAmount, 0);

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
