// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {AnyConverter, IERC20Metadata, ERC20, IERC20, Math} from "./AnyConverter.sol";

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
abstract contract AnyCompounderNaive is AnyConverter {
    using Math for uint256;
    using SafeERC20 for IERC20;

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

    error HarvestFailed();

    /**
     * @notice Claim rewards and compound them into the vault
     */
    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        (address claimContract, bytes memory claimCall, uint256 assets) = abi.decode(data, (address, bytes, uint256));

        (bool success,) = claimContract.call(claimCall);
        require(success, "Claim failed");

        uint256 ta = totalAssets();

        IERC20(yieldAsset).safeTransferFrom(msg.sender, address(this), assets);

        uint256 postTa = totalAssets();

        if (ta >= postTa) revert HarvestFailed();

        uint256 len = _rewardTokens.length;
        for (uint256 i; i < len; i++) {
            IERC20(_rewardTokens[i]).safeTransfer(msg.sender, IERC20(_rewardTokens[i]).balanceOf(address(this)));
        }

        emit Harvested();
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    error WrongToken();

    function setRewardTokens(address[] memory newRewardTokens) external onlyOwner {
        uint256 len = newRewardTokens.length;
        for (uint256 i; i < len; i++) {
            if (newRewardTokens[i] == asset() || newRewardTokens[i] == yieldAsset) revert WrongToken();
        }

        _rewardTokens = newRewardTokens;

        tokens = newRewardTokens;
        tokens.push(asset());
        tokens.push(yieldAsset);
    }
}
