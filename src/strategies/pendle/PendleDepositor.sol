// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "src/strategies/BaseStrategy.sol";
import {IPendleRouter, IPendleRouterStatic, IPendleMarket, IPendleSYToken, ISYTokenV3, ApproxParams, LimitOrderData, TokenInput, TokenOutput, SwapData} from "./IPendle.sol";

/**
 * @title   ERC4626 Pendle Protocol Vault Adapter
 * @author  ADN
 * @notice  ERC4626 wrapper for Pendle protocol
 *
 * An ERC4626 compliant Wrapper for Pendle Protocol.
 */
contract PendleDepositor is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IPendleRouter public pendleRouter;
    IPendleRouterStatic public pendleRouterStatic;
    IPendleMarket public pendleMarket;
    address public pendleSYToken;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    receive() external payable {}

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
    ) external virtual initializer {
        __PendleBase_init(asset_, owner_, autoDeposit_, strategyInitData_);
    }

    function __PendleBase_init(
        address asset_,
        address owner_,
        bool autoDeposit_,
        bytes memory strategyInitData_
    ) internal onlyInitializing {
        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        _name = string.concat(
            "VaultCraft Pendle ",
            IERC20Metadata(asset_).name(),
            " Adapter"
        );
        _symbol = string.concat("vcp-", IERC20Metadata(asset_).symbol());

        (
            address pendleMarket_,
            address pendleRouter_,
            address pendleRouterStat_
        ) = abi.decode(strategyInitData_, (address, address, address));

        pendleRouter = IPendleRouter(pendleRouter_);
        pendleMarket = IPendleMarket(pendleMarket_);
        pendleRouterStatic = IPendleRouterStatic(pendleRouterStat_);

        (address pendleSYToken_, , ) = IPendleMarket(pendleMarket_)
            .readTokens();
        pendleSYToken = pendleSYToken_;

        // make sure base asset and market are compatible
        _validateAsset(pendleSYToken_, asset_);

        // approve pendle router
        IERC20(asset_).approve(pendleRouter_, type(uint256).max);

        // approve LP token for withdrawal
        IERC20(pendleMarket_).approve(pendleRouter_, type(uint256).max);
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

    /// @notice Some pendle markets may have a supply cap, some not
    function maxDeposit(address who) public view override returns (uint256) {
        if (paused()) return 0;

        ISYTokenV3 syToken = ISYTokenV3(pendleSYToken);

        try syToken.supplyCap() returns (uint256 supplyCap) {
            uint256 syCap = supplyCap - syToken.totalSupply();

            return
                syCap.mulDiv(
                    syToken.exchangeRate(),
                    (10 ** syToken.decimals()),
                    Math.Rounding.Floor
                );
        } catch {
            return super.maxDeposit(who);
        }
    }

    function _totalAssets() internal view override returns (uint256 t) {
        uint256 lpBalance = pendleMarket.balanceOf(address(this));

        if (lpBalance == 0) {
            t = 0;
        } else {
            (t, , , , , , , ) = pendleRouterStatic
                .removeLiquiditySingleTokenStatic(
                    address(pendleMarket),
                    lpBalance,
                    asset()
                );
        }
    }

    /*//////////////////////////////////////////////////////////////
                            REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice The token rewarded from the pendle market
    function rewardTokens()
        external
        view
        virtual
        override
        returns (address[] memory)
    {
        return _getRewardTokens();
    }

    /// @notice Claim liquidity mining rewards given that it's active
    function claim() internal override returns (bool success) {
        try IPendleMarket(pendleMarket).redeemRewards(address(this)) {
            success = true;
        } catch {}
    }

    function convertToUnderlyingShares(
        uint256 assets,
        uint256 shares
    ) public view override returns (uint256) {
        revert();
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(
        uint256 amount,
        uint256,
        bytes memory data
    ) internal virtual override {
        // params suggested by docs
        ApproxParams memory approxParams = ApproxParams(
            0,
            type(uint256).max,
            0,
            256,
            1e14
        );

        // Empty structs
        LimitOrderData memory limitOrderData;
        SwapData memory swapData;

        // caching
        address asset = asset();

        TokenInput memory tokenInput = TokenInput(
            asset,
            amount,
            asset,
            address(0),
            swapData
        );
        pendleRouter.addLiquiditySingleToken(
            address(this),
            address(pendleMarket),
            data.length > 0 ? abi.decode(data, (uint256)) : 0,
            approxParams,
            tokenInput,
            limitOrderData
        );
    }

    function _protocolWithdraw(
        uint256 amount,
        uint256,
        bytes memory
    ) internal virtual override {
        // caching
        address asset = asset();

        // Empty structs
        LimitOrderData memory limitOrderData;
        SwapData memory swapData;

        TokenOutput memory tokenOutput = TokenOutput(
            asset,
            amount,
            asset,
            address(0),
            swapData
        );

        pendleRouter.removeLiquiditySingleToken(
            address(this),
            address(pendleMarket),
            amountToLp(amount, _totalAssets()),
            tokenOutput,
            limitOrderData
        );
    }

    function amountToLp(
        uint256 amount,
        uint256 totAssets
    ) internal view returns (uint256 lpAmount) {
        uint256 lpBalance = pendleMarket.balanceOf(address(this));

        amount == totAssets ? lpAmount = lpBalance : lpAmount = lpBalance
            .mulDiv(amount, totAssets, Math.Rounding.Ceil);
    }

    function _validateAsset(address syToken, address baseAsset) internal view {
        // check that vault asset is among the tokens available to mint the SY token
        address[] memory validTokens = IPendleSYToken(syToken).getTokensIn();
        bool isValidMarket;

        for (uint256 i = 0; i < validTokens.length; i++) {
            if (validTokens[i] == baseAsset) {
                isValidMarket = true;
                break;
            }
        }

        if (!isValidMarket) revert InvalidAsset();

        // and among the tokens to be redeemable from the SY token
        validTokens = IPendleSYToken(syToken).getTokensOut();
        isValidMarket = false;
        for (uint256 i = 0; i < validTokens.length; i++) {
            if (validTokens[i] == baseAsset) {
                isValidMarket = true;
                break;
            }
        }

        if (!isValidMarket) revert InvalidAsset();
    }

    function _getRewardTokens() internal view returns (address[] memory) {
        return pendleMarket.getRewardTokens();
    }

    function harvest(bytes memory) external virtual override {
        revert();
    }
}
