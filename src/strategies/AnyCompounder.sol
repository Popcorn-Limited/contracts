// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {AnyConverter, IERC20Metadata, ERC20, IERC20, Math} from "./AnyConverter.sol";
import {ContinousDutchAuction} from "src/peripheral/ContinousDutchAuction.sol";

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
abstract contract AnyCompounder is AnyConverter, ContinousDutchAuction {
    using Math for uint256;

    address[] public _rewardTokens;

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoDeposit_ Controls if `protocolDeposit` gets called on deposit
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function __AnyCompounder_init(address asset_, address owner_, bool autoDeposit_, bytes memory strategyInitData_)
        internal
        onlyInitializing
    {
        (
            bytes memory baseStrategyData,
            uint256 initPrice_,
            address paymentToken_,
            address paymentReceiver_,
            uint256 epochPeriod_,
            uint256 priceMultiplier_,
            uint256 minInitPrice_
        ) = abi.decode(strategyInitData_, (bytes, uint256, address, address, uint256, uint256, uint256));
        __AnyConverter_init(asset_, owner_, autoDeposit_, baseStrategyData);
        __ContinousDutchAuction_init(
            initPrice_, paymentToken_, paymentReceiver_, epochPeriod_, priceMultiplier_, minInitPrice_
        );
    }

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
    function harvest(bytes memory data) external override nonReentrant {
        claim();

        uint256 ta = totalAssets();

        (
            address[] memory assets,
            address assetsReceiver,
            uint256 epochId,
            uint256 deadline,
            uint256 maxPaymentTokenAmount
        ) = abi.decode(data, (address[], address, uint256, uint256, uint256));

        buy(assets, assetsReceiver, epochId, deadline, maxPaymentTokenAmount);

        uint256 postTa = totalAssets();

        if (ta >= postTa) revert HarvestFailed();

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
