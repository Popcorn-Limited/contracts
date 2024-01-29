// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {IConvexBooster, IConvexRewards, IRewards} from "./IConvex.sol";
import {ICurveMetapool} from "../../../interfaces/external/curve/ICurveMetapool.sol";
import {ICurveRouter} from "../../../interfaces/external/curve/ICurveRouter.sol";

struct CurveRoute {
    address[9] route;
    uint256[3][4] swapParams;
}

/**
 * @title   Convex Compounder Adapter
 * @author  ADiNenno
 * @notice  ERC4626 wrapper for Convex Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/convex-eth/platform/blob/main/contracts/contracts/Booster.sol.
 * Allows wrapping Convex Vaults with or without an active convexBooster.
 * Compounds rewards into the vault underlying.
 */
contract ConvexCompounder is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The poolId inside Convex booster for relevant Curve lpToken.
    uint256 public pid;

    /// @notice The booster address for Convex
    IConvexBooster public convexBooster;

    /// @notice The Convex convexRewards.
    IConvexRewards public convexRewards;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error AssetMismatch();

    /**
     * @notice Initialize a new Convex Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry The Convex Booster contract
     * @param convexInitData Encoded data for the convex adapter initialization.
     * @dev `_pid` - The poolId for lpToken.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory convexInitData
    ) external initializer {
        uint256 _pid = abi.decode(convexInitData, (uint256));

        convexBooster = IConvexBooster(registry);
        pid = _pid;

        (address _asset, , , address _convexRewards, , ) = convexBooster
            .poolInfo(pid);

        convexRewards = IConvexRewards(_convexRewards);

        __AdapterBase_init(adapterInitData);

        if (_asset != asset()) revert AssetMismatch();

        _name = string.concat(
            "VaultCraft Convex ",
            IERC20Metadata(_asset).name(),
            " Adapter"
        );
        _symbol = string.concat("vcCvx-", IERC20Metadata(_asset).symbol());

        IERC20(_asset).approve(address(convexBooster), type(uint256).max);
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
    function rewardTokens()
        external
        view
        override
        returns (address[] memory tokens)
    {
        uint256 len = convexRewards.extraRewardsLength();

        tokens = new address[](len + 2);
        tokens[0] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV
        tokens[1] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B; // CVX

        for (uint256 i; i < len; i++) {
            tokens[i + 1] = convexRewards.extraRewards(i).rewardToken();
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into Convex convexBooster contract.
    function _protocolDeposit(uint256 amount, uint256) internal override {
        convexBooster.deposit(pid, amount, true);
    }

    /// @notice Withdraw from Convex convexRewards contract.
    function _protocolWithdraw(uint256 amount, uint256) internal override {
        /**
         * @dev No need to convert as Convex shares are 1:1 with Curve deposits.
         * @param amount Amount of shares to withdraw.
         * @param claim Claim rewards on withdraw?
         */
        convexRewards.withdrawAndUnwrap(amount, false);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256[] internal minTradeAmounts; // ordered as in rewardsTokens()
    address internal curveRouter;
    address internal baseAsset;

    mapping(address => CurveRoute) internal rewardRoutes; // to swap reward token to baseAsset
    CurveRoute internal lpRoute; // to add liquidity (ie swapping from baseAsset to lpToken via curve router)

    error InvalidHarvestValues();

    function setHarvestValues(
        address curveRouter_,
        address baseAsset_,
        uint256[] memory minTradeAmounts_,
        CurveRoute memory lpRoute_,
        CurveRoute[] memory routes_
    ) public onlyOwner {
        address[] memory rewTokens = this.rewardTokens();
        uint256 len = rewTokens.length;

        _verifyRewardData(
            rewTokens,
            minTradeAmounts_,
            len,
            routes_,
            baseAsset_
        );

        _verifyLpRoute(baseAsset_, lpRoute_);

        lpRoute = lpRoute_;
        curveRouter = curveRouter_;
        minTradeAmounts = minTradeAmounts_;
        _approveRewards(rewTokens);

        baseAsset = baseAsset_;
        IERC20(baseAsset).approve(curveRouter, type(uint256).max);

        for (uint256 i = 0; i < len; i++) {
            rewardRoutes[rewTokens[i]] = routes_[i];
        }
    }

    /**
     * @notice Claim rewards and compound them into the vault
     */
    function harvest() public override takeFees {
        if ((lastHarvest + harvestCooldown) < block.timestamp) {
            this.claim();

            ICurveRouter router = ICurveRouter(curveRouter);

            // swap all reward tokens to base asset
            _swapToBaseAsset(router);

            // add liquidity via router
            _addLiquidity(router);

            // add liquidity - get LP token
            _protocolDeposit(IERC20(asset()).balanceOf(address(this)), 0);

            lastHarvest = block.timestamp;
        }

        emit Harvested();
    }

    function _verifyLpRoute(
        address base,
        CurveRoute memory toLpRoute
    ) internal view {
        address asset = asset();

        // Verify base asset to lp token path
        if (base != asset) {
            if (toLpRoute.route[0] != base) revert InvalidHarvestValues();

            // Loop through the route until there are no more token or the array is over
            uint8 i = 1;
            while (i < 9) {
                if (i == 8 || toLpRoute.route[i + 1] == address(0)) break;
                i++;
            }
            if (toLpRoute.route[i] != asset) revert InvalidHarvestValues();
        }
    }

    function _verifyRewardData(
        address[] memory rewTokens,
        uint256[] memory minAmounts,
        uint256 len,
        CurveRoute[] memory toBaseAssetRoutes,
        address base
    ) internal pure {
        if (toBaseAssetRoutes.length != len) revert InvalidHarvestValues();

        for (uint256 i; i < len; i++) {
            // verify min amount
            require(minAmounts[i] != 0, "min trade amount must be > 0");

            // Verify base asset to asset path
            if (toBaseAssetRoutes[i].route[0] != rewTokens[i])
                revert InvalidHarvestValues();

            // Loop through the route until there are no more token or the array is over
            uint8 y = 1;
            while (y < 9) {
                if (y == 8 || toBaseAssetRoutes[i].route[y + 1] == address(0))
                    break;
                y++;
            }
            if (toBaseAssetRoutes[i].route[y] != base)
                revert InvalidHarvestValues();
        }
    }

    /// @notice Leverage the curve router to add liquidity
    function _addLiquidity(ICurveRouter router) internal {
        router.exchange_multiple(
            lpRoute.route,
            lpRoute.swapParams,
            IERC20(baseAsset).balanceOf(address(this)),
            0
        );
    }

    /// @notice Leverage the curve router to swap all rewards into a base asset
    function _swapToBaseAsset(ICurveRouter router) internal {
        address[] memory rewTokens = this.rewardTokens();

        uint256 rewLen = rewTokens.length;

        for (uint256 i = 0; i < rewLen; i++) {
            IERC20 rewToken = IERC20(rewTokens[i]);
            uint256 inputBalance = rewToken.balanceOf(address(this));

            if (inputBalance > minTradeAmounts[i]) {
                CurveRoute memory routeData = rewardRoutes[address(rewToken)];
                router.exchange_multiple(
                    routeData.route,
                    routeData.swapParams,
                    inputBalance,
                    0
                );
            }
        }
    }

    /// @notice Claim liquidity mining rewards given that it's active
    function claim() public override onlyStrategy returns (bool success) {
        try convexRewards.getReward(address(this), true) {
            success = true;
        } catch {}
    }

    function _approveRewards(address[] memory rewTokens) internal {
        for (uint256 i = 0; i < rewTokens.length; i++) {
            IERC20(rewTokens[i]).approve(curveRouter, type(uint256).max);
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
