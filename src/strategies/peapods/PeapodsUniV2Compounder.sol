// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {PeapodsDepositor, IERC20, SafeERC20} from "./PeapodsStrategy.sol";
import {BaseUniV2LpCompounder, SwapStep} from "src/peripheral/compounder/uni/v2/BaseUniV2LpCompounder.sol";

/**
 * @title   ERC4626 Peapods Protocol Vault Adapter
 * @author  ADN
 * @notice  ERC4626 wrapper for Peapods protocol
 *
 * An ERC4626 compliant Wrapper for Peapods.
 * Implements harvest func that swaps via Uniswap V2
 */
contract PeapodsUniV2Compounder is PeapodsDepositor, BaseUniV2LpCompounder {
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

        sellRewardsForLpTokenViaUniswap(asset_, address(this), block.timestamp, data);

        _protocolDeposit(IERC20(asset_).balanceOf(address(this)), 0, data);

        emit Harvested();
    }

    function setHarvestValues(
        address[] memory rewTokens,
        address newRouter,
        address[2] memory newDepositAssets,
        SwapStep[] memory newSwaps
    ) external onlyOwner {
        setUniswapLpCompounderValues(newRouter, newDepositAssets, rewTokens, newSwaps);
    }

    // allow owner to withdraw eventual dust amount of tokens
    // from the compounding operation
    function withdrawDust(address token) external onlyOwner {
        if (token != depositAssets[0] && token != depositAssets[1]) {
            revert("Invalid Token");
        }

        IERC20(token).safeTransfer(owner, IERC20(token).balanceOf(address(this)));
    }
}
