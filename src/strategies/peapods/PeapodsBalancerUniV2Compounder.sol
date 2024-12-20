// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {PeapodsDepositor, IERC20, SafeERC20} from "./PeapodsStrategy.sol";
import {BaseBalancerLpCompounder, HarvestValues, TradePath} from "src/peripheral/compounder/balancer/BaseBalancerLpCompounder.sol";
import {BaseUniV2Compounder, SwapStep} from "src/peripheral/compounder/uni/v2/BaseUniV2Compounder.sol";

/**
 * @title   ERC4626 Peapods Protocol Vault Adapter
 * @author  ADN
 * @notice  ERC4626 wrapper for Peapods protocol
 *
 * An ERC4626 compliant Wrapper for Peapods.
 * Implements harvest func that swaps via Balancer
 */
contract PeapodsBalancerUniV2Compounder is PeapodsDepositor, BaseBalancerLpCompounder, BaseUniV2Compounder {
    using SafeERC20 for IERC20;

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
    function initialize(address asset_, address owner_, bool autoDeposit_, bytes memory strategyInitData_)
        external
        override
        initializer
    {
        __PeapodsBase_init(asset_, owner_, autoDeposit_, strategyInitData_);
    }

    /*//////////////////////////////////////////////////////////////
                            REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice The token rewarded from the pendle market
    function rewardTokens() external view override returns (address[] memory) {
        return sellTokens;
    }

    /*//////////////////////////////////////////////////////////////
                            HARVESGT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim rewards, swaps to asset and add liquidity
     */
    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        claim();

        // caching
        address asset_ = asset();

        // sell for a balancer asset via univ2
        sellRewardsViaUniswapV2();

        // sell the balancer asset for deposit asset and add liquidity
        sellRewardsForLpTokenViaBalancer(asset_, data);

        // compound the lp token
        _protocolDeposit(IERC20(asset_).balanceOf(address(this)), 0, data);

        emit Harvested();
    }

    function setHarvestValues(
        address newBalancerVault,
        TradePath[] memory newTradePaths,
        HarvestValues memory harvestValues_,
        address newUniswapRouter,
        address[] memory rewTokens,
        SwapStep[] memory newSwapSteps
    ) external onlyOwner {
        setBalancerLpCompounderValues(newBalancerVault, newTradePaths, harvestValues_);
        setUniswapTradeValues(newUniswapRouter, rewTokens, newSwapSteps);
    }
}
