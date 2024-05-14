// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../../../BaseStrategy.sol";
import {ICurveLp, IGauge, ICurveRouter, CurveSwap} from "./IArbCurve.sol";

/**
 * @title   Curve Child Gauge Adapter
 * @notice  ERC4626 wrapper for  Curve Child Gauge Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/curvefi/curve-xchain-factory/blob/master/contracts/implementations/ChildGauge.vy.
 * Allows wrapping Curve Child Gauge Vaults.
 */
contract CurveGaugeSingleAssetCompounder is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    address public lpToken;
    IGauge public gauge;
    int128 public indexIn;
    uint256 public nCoins;

    uint256 public discountBps;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

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
        (address _lpToken, address _gauge, int128 _indexIn) = abi.decode(
            strategyInitData_,
            (address, address, int128)
        );

        lpToken = _lpToken;
        gauge = IGauge(_gauge);
        indexIn = _indexIn;
        nCoins = ICurveLp(_lpToken).N_COINS();

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(_lpToken).approve(_gauge, type(uint256).max);
        IERC20(asset()).approve(_lpToken, type(uint256).max);

        _name = string.concat(
            "VaultCraft CurveGaugeSingleAssetCompounder ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-sccrv-", IERC20Metadata(asset()).symbol());
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
                ? (((ICurveLp(lpToken).get_virtual_price() * lpBal) / 1e18) *
                    (10_000 - discountBps)) / 10_000
                : 0;
    }

    /// @notice The token rewarded from the convex reward contract
    function rewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(
        uint256 assets,
        uint256,
        bytes memory data
    ) internal override {
        uint256[] memory amounts = new uint256[](nCoins);
        amounts[uint256(uint128(indexIn))] = assets;

        ICurveLp(lpToken).add_liquidity(
            amounts,
            data.length > 0 ? abi.decode(data, (uint256)) : 0
        );
        gauge.deposit(IERC20(lpToken).balanceOf(address(this)));
    }

    function _protocolWithdraw(
        uint256 assets,
        uint256 shares
    ) internal override {
        uint256 lpWithdraw = shares.mulDiv(
            IERC20(address(gauge)).balanceOf(address(this)),
            totalSupply(),
            Math.Rounding.Ceil
        );

        gauge.withdraw(lpWithdraw);

        ICurveLp(lpToken).remove_liquidity_one_coin(lpWithdraw, indexIn, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    error CompoundFailed();

    /// @notice Claim rewards from the gauge
    function claim() internal override returns (bool success) {
        try gauge.claim_rewards() {
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

        (uint256 minOut, bytes memory depositData) = abi.decode(
            data,
            (uint256, bytes)
        );

        amount = IERC20(asset()).balanceOf(address(this));
        if (amount < minOut) revert CompoundFailed();

        _protocolDeposit(amount, 0, depositData);

        emit Harvested();
    }

    address[] internal _rewardTokens;

    ICurveRouter public curveRouter;

    mapping(address => CurveSwap) internal swaps; // to swap reward token to baseAsset

    error InvalidHarvestValues();

    function setHarvestValues(
        address curveRouter_,
        address[] memory rewardTokens_,
        CurveSwap[] memory swaps_, // must be ordered like rewardTokens_
        uint256 discountBps_
    ) public onlyOwner {

        discountBps = discountBps_;
    }
}
