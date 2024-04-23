// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../BaseStrategy.sol";
import {IAuraBooster, IAuraRewards, IAuraStaking} from "./IAura.sol";
import {IBalancerVault, SwapKind, IAsset, BatchSwapStep, FundManagement, JoinPoolRequest} from "../../interfaces/external/balancer/IBalancerVault.sol";

struct AuraValues {
    address auraBooster;
    bytes32 balPoolId;
    address balVault;
    uint256 pid;
    address[] underlyings;
}

struct HarvestValues {
    uint256 amountsInLen;
    address baseAsset;
    uint256 indexIn;
    uint256 indexInUserData;
}

struct HarvestTradePath {
    IAsset[] assets;
    int256[] limits;
    uint256 minTradeAmount;
    BatchSwapStep[] swaps;
}

struct TradePath {
    IAsset[] assets;
    int256[] limits;
    uint256 minTradeAmount;
    bytes swaps;
}

/**
 * @title  Aura Adapter
 * @author amatureApe
 * @notice ERC4626 wrapper for Aura Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/sushiswap/sushiswap/blob/archieve/canary/contracts/Aura.sol.
 * Allows wrapping Aura Vaults.
 */
contract AuraCompounder is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    AuraValues internal auraValues;

    IAuraRewards public auraRewards;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoHarvest_ Controls if the harvest function gets called on deposit/withdrawal
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function initialize(
        address asset_,
        address owner_,
        bool autoHarvest_,
        bytes memory strategyInitData_
    ) external initializer {
        AuraValues memory auraValues_ = abi.decode(
            strategyInitData_,
            (AuraValues)
        );

        auraValues = auraValues_;

        (address balancerLpToken_, , , address auraRewards_, , ) = IAuraBooster(
            auraValues_.auraBooster
        ).poolInfo(auraValues_.pid);

        auraRewards = IAuraRewards(auraRewards_);

        if (balancerLpToken_ != asset_) revert InvalidAsset();

        __BaseStrategy_init(asset_, owner_, autoHarvest_);

        IERC20(balancerLpToken_).approve(
            auraValues_.auraBooster,
            type(uint256).max
        );

        _name = string.concat(
            "VaultCraft Aura ",
            IERC20Metadata(asset_).name(),
            " Adapter"
        );
        _symbol = string.concat("vcAu-", IERC20Metadata(asset_).symbol());
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
        return auraRewards.balanceOf(address(this));
    }

    /// @notice The token rewarded
    function rewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 assets, uint256) internal override {
        // Caching
        AuraValues memory auraValues_ = auraValues;
        IAuraBooster(auraValues_.auraBooster).deposit(
            auraValues_.pid,
            assets,
            true
        );
    }

    function _protocolWithdraw(
        uint256 assets,
        uint256,
        address recipient
    ) internal override {
        auraRewards.withdrawAndUnwrap(assets, true);
        IERC20(asset()).safeTransfer(recipient, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim rewards from the aura
    function claim() public override returns (bool success) {
        try auraRewards.getReward() {
            success = true;
        } catch {}
    }

    /**
     * @notice Execute Strategy and take fees.
     */
    function harvest() public override takeFees {
        claim();

        // Caching
        AuraValues memory auraValues_ = auraValues;
        address[] memory rewardTokens_ = _rewardTokens;
        HarvestValues memory harvestValues_ = harvestValues;

        // Trade to base asset
        uint256 len = rewardTokens_.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 rewardBal = IERC20(rewardTokens_[i]).balanceOf(
                address(this)
            );

            // More caching
            TradePath memory tradePath = tradePaths[i];
            if (rewardBal >= tradePath.minTradeAmount) {
                // Decode since nested struct[] isnt allowed in storage
                BatchSwapStep[] memory swaps = abi.decode(
                    tradePath.swaps,
                    (BatchSwapStep[])
                );
                // Use the actual rewardBal as the amount to sell
                swaps[0].amount = rewardBal;

                // Swap to base asset
                IBalancerVault(auraValues_.balVault).batchSwap(
                    SwapKind.GIVEN_IN,
                    swaps,
                    tradePath.assets,
                    FundManagement(
                        address(this),
                        false,
                        payable(address(this)),
                        false
                    ),
                    tradePath.limits,
                    block.timestamp
                );
            }
        }
        // Get the required Lp Token
        uint256 poolAmount = IERC20(harvestValues_.baseAsset).balanceOf(
            address(this)
        );
        if (poolAmount > 0) {
            uint256[] memory amounts = new uint256[](
                auraValues_.underlyings.length
            );
            // Use the actual base asset balance to pool.
            amounts[harvestValues_.indexIn] = poolAmount;

            // Some pools need to be encoded with a different length array than the actual input amount array
            bytes memory userData;
            if (auraValues_.underlyings.length != harvestValues_.amountsInLen) {
                uint256[] memory amountsIn = new uint256[](
                    harvestValues_.amountsInLen
                );
                amountsIn[harvestValues_.indexInUserData] = poolAmount;
                userData = abi.encode(1, amountsIn, 0); // Exact In Enum, inAmounts, minOut
            } else {
                userData = abi.encode(1, amounts, 0); // Exact In Enum, inAmounts, minOut
            }

            // Pool base asset
            IBalancerVault(auraValues_.balVault).joinPool(
                auraValues_.balPoolId,
                address(this),
                address(this),
                JoinPoolRequest(
                    auraValues_.underlyings,
                    amounts,
                    userData,
                    false
                )
            );

            // redeposit
            _protocolDeposit(IERC20(asset()).balanceOf(address(this)), 0);
        }

        emit Harvested();
    }

    HarvestValues internal harvestValues;
    TradePath[] internal tradePaths;
    address[] internal _rewardTokens;

    function setHarvestValues(
        HarvestValues memory harvestValues_,
        HarvestTradePath[] memory tradePaths_
    ) external onlyOwner {
        // Remove old rewardToken
        for (uint i; i < _rewardTokens.length; ) {
            IERC20(_rewardTokens[0]).approve(auraValues.balVault, 0);
            unchecked {
                ++i;
            }
        }
        delete _rewardTokens;

        // Add new rewardToken
        for (uint i; i < tradePaths_.length; ) {
            _rewardTokens.push(address(tradePaths_[i].assets[0]));
            IERC20(address(tradePaths_[i].assets[0])).approve(
                auraValues.balVault,
                type(uint).max
            );
            unchecked {
                ++i;
            }
        }

        // Reset old base asset
        if (harvestValues.baseAsset != address(0)) {
            IERC20(harvestValues.baseAsset).approve(auraValues.balVault, 0);
        }
        // approve and set new base asset
        IERC20(harvestValues_.baseAsset).approve(
            auraValues.balVault,
            type(uint).max
        );
        harvestValues = harvestValues_;

        //Set new trade paths
        delete tradePaths;
        for (uint i; i < tradePaths_.length; ) {
            tradePaths.push(
                TradePath({
                    assets: tradePaths_[i].assets,
                    limits: tradePaths_[i].limits,
                    minTradeAmount: tradePaths_[i].minTradeAmount,
                    swaps: abi.encode(tradePaths_[i].swaps)
                })
            );
            unchecked {
                ++i;
            }
        }
    }
}
