// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../../../BaseStrategy.sol";
import {ICurveLp, IGauge, ICurveRouter, CurveSwap, IMinter} from "../../ICurve.sol";

/**
 * @title   Curve Child Gauge Adapter
 * @notice  ERC4626 wrapper for  Curve Child Gauge Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/curvefi/curve-xchain-factory/blob/master/contracts/implementations/ChildGauge.vy.
 * Allows wrapping Curve Child Gauge Vaults.
 */
contract CurveGaugeCompounder is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IMinter internal minter;
    ICurveLp public pool;
    IGauge public gauge;
    uint256 internal nCoins;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoHarvest_ Controls if the harvest function gets called on deposit/withdrawal
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function initialize(
        address asset_,
        address owner_,
        bool autoHarvest_,
        bytes memory strategyInitData_
    ) external initializer {
        __BaseStrategy_init(asset_, owner_, autoHarvest_);

        (address _gauge, address _pool, address _minter) = abi.decode(
            strategyInitData_,
            (address, address, address)
        );

        minter = IMinter(_minter);
        gauge = IGauge(_gauge);
        pool = ICurveLp(_pool);

        nCoins = pool.N_COINS();

        _name = string.concat(
            "VaultCraft CurveGaugeCompounder ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-sccrv-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).approve(_gauge, type(uint256).max);
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
        return IERC20(address(gauge)).balanceOf(address(this));
    }

    /// @notice The token rewarded from the convex reward contract
    function rewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 assets, uint256) internal override {
        gauge.deposit(assets);
    }

    function _protocolWithdraw(
        uint256 assets,
        uint256,
        address recipient
    ) internal override {
        gauge.withdraw(assets);
        IERC20(asset()).safeTransfer(recipient, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim rewards from the gauge
    function claim() public override returns (bool success) {
        try gauge.claim_rewards() {
            try minter.mint(address(gauge)) {
                success = true;
            } catch {}
        } catch {}
    }

    /**
     * @notice Claim rewards and compound them into the vault
     */
    function harvest() public override takeFees {
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

        amount = IERC20(depositAsset).balanceOf(address(this));
        if (amount > 0) {
            uint256[] memory amounts = new uint256[](nCoins);
            amounts[uint256(uint128(indexIn))] = amount;

            ICurveLp(pool).add_liquidity(amounts, 0);

            address asset_ = asset();
            _protocolDeposit(IERC20(asset_).balanceOf(address(this)), 0);
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

    address[] internal _rewardTokens;
    uint256[] public minTradeAmounts; // ordered as in rewardsTokens()

    ICurveRouter public curveRouter;

    mapping(address => CurveSwap) internal swaps; // to swap reward token to baseAsset

    address internal depositAsset;
    int128 internal indexIn;

    error InvalidHarvestValues();

    function setHarvestValues(
        address curveRouter_,
        address[] memory rewardTokens_,
        uint256[] memory minTradeAmounts_, // must be ordered like rewardTokens_
        CurveSwap[] memory swaps_, // must be ordered like rewardTokens_
        int128 indexIn_
    ) public onlyOwner {
        curveRouter = ICurveRouter(curveRouter_);

        _approveSwapTokens(rewardTokens_, curveRouter_);
        for (uint256 i = 0; i < rewardTokens_.length; i++) {
            swaps[rewardTokens_[i]] = swaps_[i];
        }

        ICurveLp _pool = pool;
        address depositAsset_ = _pool.coins(uint256(uint128(indexIn_)));

        if (depositAsset != address(0))
            IERC20(depositAsset).approve(address(_pool), 0);
        IERC20(depositAsset_).approve(address(_pool), type(uint256).max);

        depositAsset = depositAsset_;
        indexIn = indexIn_;

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
}
