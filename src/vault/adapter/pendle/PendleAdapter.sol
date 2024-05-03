// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter, IERC4626} from "../abstracts/AdapterBase.sol";
import {IPendleRouter, IPendleRouterStatic, IPendleMarket, IPendleSYToken, ISYTokenV3, ApproxParams, LimitOrderData, TokenInput, TokenOutput, SwapData} from "./IPendle.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";

/**
 * @title   ERC4626 Pendle Protocol Vault Adapter
 * @author  ADN
 * @notice  ERC4626 wrapper for Pendle protocol
 *
 * An ERC4626 compliant Wrapper for Pendle Protocol.
 */
contract PendleAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IPendleRouter public pendleRouter;
    IPendleRouterStatic public pendleRouterStatic;
    address public pendleSYToken;
    address public pendleMarket;
    uint256 public swapDelay;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error NotEndorsed();
    error InvalidAsset();

    receive() external payable {}

    /**
     * @notice Initialize a new generic Vault Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address _pendleRouter,
        bytes memory pendleInitData
    ) external virtual initializer {
        __PendleBase_init(adapterInitData, _pendleRouter, pendleInitData);
    }

    function __PendleBase_init(
        bytes memory adapterInitData,
        address _pendleRouter,
        bytes memory pendleInitData
    ) internal onlyInitializing {
        __AdapterBase_init(adapterInitData);

        address baseAsset = asset();

        _name = string.concat(
            "VaultCraft Pendle ",
            IERC20Metadata(baseAsset).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-", IERC20Metadata(baseAsset).symbol());

        pendleRouter = IPendleRouter(_pendleRouter);
        address _pendleRouterStat;

        (pendleMarket, _pendleRouterStat, swapDelay) = abi.decode(
            pendleInitData,
            (address, address, uint256)
        );

        pendleRouterStatic = IPendleRouterStatic(_pendleRouterStat);

        (pendleSYToken, , ) = IPendleMarket(pendleMarket).readTokens();

        // make sure base asset and market are compatible
        _validateAsset(pendleSYToken, baseAsset);

        // approve pendle router
        IERC20(baseAsset).approve(_pendleRouter, type(uint256).max);

        // approve LP token for withdrawal
        IERC20(pendleMarket).approve(_pendleRouter, type(uint256).max);
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
        try ISYTokenV3(pendleSYToken).supplyCap() returns (uint256 supplyCap) {
            return supplyCap - ISYTokenV3(pendleSYToken).totalSupply();
        } catch {
            return super.maxDeposit(who);
        }
    }

    function _totalAssets() internal view override returns (uint256 t) {
        uint256 lpBalance = IERC20(pendleMarket).balanceOf(address(this));
        address asset = asset();

        if (lpBalance == 0) {
            t = 0;
        } else {
            (t, , , , , , , ) = pendleRouterStatic
                .removeLiquiditySingleTokenStatic(
                    pendleMarket,
                    lpBalance,
                    asset
                );
        }

        // floating amount
        t += IERC20(asset).balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    function setSwapDelay(uint256 newDelay) public onlyOwner {
        swapDelay = newDelay;
    }

    /*//////////////////////////////////////////////////////////////
                            REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice The token rewarded from the pendle market
    function rewardTokens() external view override returns (address[] memory) {
        return _getRewardTokens();
    }

    /// @notice Claim liquidity mining rewards given that it's active
    function claim() public override returns (bool success) {
        try IPendleMarket(pendleMarket).redeemRewards(address(this)) {
            success = true;
        } catch {}
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(
        uint256 amount,
        uint256
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

        address asset = asset();
        uint256 netInput = amount == maxDeposit(address(this))
            ? amount
            : IERC20(asset).balanceOf(address(this)); // amount + eventual floating

        TokenInput memory tokenInput = TokenInput(
            asset,
            netInput,
            asset,
            address(0),
            swapData
        );
        pendleRouter.addLiquiditySingleToken(
            address(this),
            pendleMarket,
            0,
            approxParams,
            tokenInput,
            limitOrderData
        );
    }

    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal virtual override {
        address asset = asset();

        // sub floating 
        uint256 protocolAmount = amount - IERC20(asset).balanceOf(address(this));

        // Empty structs
        LimitOrderData memory limitOrderData;
        SwapData memory swapData;

        TokenOutput memory tokenOutput = TokenOutput(
            asset,
            protocolAmount,
            asset,
            address(0),
            swapData
        );

        pendleRouter.removeLiquiditySingleToken(
            address(this),
            pendleMarket,
            amountToLp(amount, totalAssets()),
            tokenOutput,
            limitOrderData
        );
    }

    function amountToLp(
        uint256 amount,
        uint256 totAssets
    ) internal view returns (uint256 lpAmount) {
        uint256 lpBalance = IERC20(pendleMarket).balanceOf(address(this));

        amount == totAssets 
            ? lpAmount = lpBalance
            : lpAmount = lpBalance.mulDiv(amount, totAssets, Math.Rounding.Ceil);
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

    function _getRewardTokens() internal view returns (address[] memory){
        return IPendleMarket(pendleMarket).getRewardTokens();
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
