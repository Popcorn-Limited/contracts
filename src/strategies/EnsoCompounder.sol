// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {EnsoConverter, IERC20Metadata, ERC20, IERC20, Math} from "./EnsoConverter.sol";

/**
 * @title   BaseStrategy
 * @author  RedVeil
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 *
 * The ERC4626 compliant base contract for all adapter contracts.
 * It allows interacting with an underlying protocol.
 * All specific interactions for the underlying protocol need to be overriden in the actual implementation.
 * The adapter can be initialized with a strategy that can perform additional operations. (Leverage, Compounding, etc.)
 */
abstract contract EnsoCompounder is EnsoConverter {
    using Math for uint256;

    address[] public _rewardTokens;

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice The token rewarded from the convex reward contract
    function rewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim rewards and compound them into the vault
     */
    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        claim();

        (bytes memory tradeData, bytes memory postPushData) = abi.decode(
            data,
            (bytes, bytes)
        );

        (bool success, bytes memory returnData) = ensoRouter.call(tradeData);
        if (success) {
            uint256 bal = IERC20(asset()).balanceOf(address(this));

            // Make sure float stays in the strategy for withdrawals
            uint256 depositAmount = bal -
                bal.mulDiv(10_000 - floatRatio, 10_000, Math.Rounding.Floor);

            _postPushCall(
                depositAmount,
                convertToShares(depositAmount),
                postPushData
            );
        }

        emit Harvested();
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    function setRewardTokens(
        address[] memory newRewardTokens
    ) external onlyOwner {
        // Remove old rewardToken allowance
        _approveTokens(_rewardTokens, ensoRouter, 0);

        // Add new rewardToken allowance
        _approveTokens(newRewardTokens, ensoRouter, type(uint256).max);

        _rewardTokens = newRewardTokens;
        
        tokens = newRewardTokens;
        tokens.push(asset());
        tokens.push(yieldAsset);
    }
}
