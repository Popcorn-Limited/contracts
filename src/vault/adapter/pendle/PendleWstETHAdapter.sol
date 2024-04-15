// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter, IERC4626} from "../abstracts/AdapterBase.sol";
import {IPendleRouter, IwstETH, IPendleMarket, IPendleSYToken, IPendleOracle, ApproxParams, LimitOrderData, TokenInput, TokenOutput, SwapData} from "./IPendle.sol";
import {PendleAdapter} from "./PendleAdapter.sol";
import {IBalancerRouter, SingleSwap, FundManagement, SwapKind} from "./IBalancer.sol";

/**
 * @title   ERC4626 Pendle Protocol Vault Adapter
 * @author  ADN
 * @notice  ERC4626 wrapper for Pendle protocol
 *
 * An ERC4626 compliant Wrapper for Pendle Protocol.
 * Only with wstETH base asset
 */

struct BalancerRewardTokenData {
    address[] pathAddresses; // orderered list of tokens, last one must be asset()
    bytes32[] poolIds; // ordered list of poolIds to swap from
    uint256 minTradeAmount; //min amount of reward tokens to execute swaps
}

contract PendleWstETHAdapter is PendleAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    BalancerRewardTokenData[] rewardTokensData; // ordered as in _rewardTokens

    IBalancerRouter public constant balancerRouter =
        IBalancerRouter(address(0xBA12222222228d8Ba445958a75a0704d566BF2C8));

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize a new generic wstETH Pendle Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address _pendleRouter,
        bytes memory pendleInitData
    ) external override(PendleAdapter) initializer {
        __PendleBase_init(adapterInitData, _pendleRouter, pendleInitData);

        address baseAsset = asset();
        require(
            baseAsset == 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            "Only wstETH"
        );
    }
    
    function _toAssetRate() internal view override returns (uint256 rate) {
        rate = super._toAssetRate();

        // apply eth to wsteth ratio
        uint256 ethRate = IwstETH(asset()).getWstETHByStETH(1 ether);
        rate = rate.mulDiv(ethRate, 1e18, Math.Rounding.Floor);
    }

    /*//////////////////////////////////////////////////////////////
                            HARVESGT LOGIC
    //////////////////////////////////////////////////////////////*/

    function setHarvestData(
        BalancerRewardTokenData[] memory rewData
    ) external onlyOwner {
        uint256 len = rewData.length;
        require(len == _rewardTokens.length, "Invalid length");

        for (uint256 i = 0; i < len; i++) {
            rewardTokensData.push(rewData[i]);
            _approveSwapTokens(rewData[i].pathAddresses, address(balancerRouter));
        }
    }

    /**
     * @notice Claim rewards, swaps to asset and add liquidity
     */
    function harvest() public override takeFees {
        if ((lastHarvest + harvestCooldown) < block.timestamp) {
            claim();

            uint256 amount;
            uint256 rewLen = _rewardTokens.length;

            // swap each reward token to the vault asset
            for (uint256 i = 0; i < rewLen; i++) {
                address rewardToken = _rewardTokens[i];
                amount = IERC20(rewardToken).balanceOf(address(this));

                BalancerRewardTokenData memory rewData = rewardTokensData[i];
                if (amount > rewData.minTradeAmount) {
                    // perform all the balancer single swaps for this reward token
                    for (uint256 j = 0; j < rewData.poolIds.length; j++) {
                        amount = _singleBalancerSwap(
                            rewData.pathAddresses[j],
                            rewData.pathAddresses[j + 1],
                            amount,
                            rewData.poolIds[j]
                        );
                    }
                }
            }

            // get all the base asset and add liquidity
            amount = IERC20(asset()).balanceOf(address(this));
            if (amount > 0) {
                _protocolDeposit(amount, 0);
            }

            lastHarvest = block.timestamp;
        }

        emit Harvested();
    }

    function _approveSwapTokens(address[] memory assets, address router) internal {
        uint256 len = assets.length;
        if (len > 0) {
            // void approvals
            for (uint256 i = 0; i < len - 1; i++) {
                IERC20(assets[i]).approve(router, 0);
            }
        }

        for (uint256 i = 0; i < len - 1; i++) {
            IERC20(assets[i]).approve(
                router,
                type(uint256).max
            );
        }
    }

    function _singleBalancerSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes32 poolId
    ) internal returns (uint256 amountOut) {
        SingleSwap memory swap = SingleSwap(
            poolId,
            SwapKind.GIVEN_IN,
            tokenIn,
            tokenOut,
            amountIn,
            hex""
        );

        FundManagement memory fundManagement = FundManagement(
            payable(address(this)),
            false,
            payable(address(this)),
            false
        );

        amountOut = balancerRouter.swap(
            swap,
            fundManagement,
            0,
            block.timestamp + swapDelay
        );
    }
}