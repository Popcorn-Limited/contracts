// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IPendleMarket} from "./IPendle.sol";
import {PendleDepositor, IERC20} from "./PendleDepositor.sol";
import {BaseBalancerCompounder, TradePath} from "../../peripheral/BaseBalancerCompounder.sol";
import {BaseCurveCompounder, CurveSwap} from "../../peripheral/BaseCurveCompounder.sol";

/**
 * @title   ERC4626 Pendle Protocol Vault Adapter
 * @author  ADN
 * @notice  ERC4626 wrapper for Pendle protocol
 *
 * An ERC4626 compliant Wrapper for Pendle Protocol.
 * Implements harvest func that swaps via balancer and curve
 */
contract PendleBalancerCurveCompounder is PendleDepositor, BaseBalancerCompounder, BaseCurveCompounder {
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
        virtual
        initializer
    {
        __PendleBase_init(asset_, owner_, autoDeposit_, strategyInitData_);
    }

    /*//////////////////////////////////////////////////////////////
                            REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice The token rewarded from the pendle market
    function rewardTokens() external view override returns (address[] memory) {
        return _balancerSellTokens;
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

        sellRewardsViaBalancer();
        sellRewardsViaCurve();

        _protocolDeposit(IERC20(asset_).balanceOf(address(this)), 0, data);

        emit Harvested();
    }

    function setHarvestValues(
        address newBalancerVault,
        TradePath[] memory newTradePaths,
        address newCurveRouter,
        CurveSwap[] memory newCurveSwaps
    ) external onlyOwner {
        setBalancerTradeValues(newBalancerVault, newTradePaths);
        setCurveTradeValues(newCurveRouter, newCurveSwaps);
    }
}
