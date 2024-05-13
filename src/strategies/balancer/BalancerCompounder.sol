// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../BaseStrategy.sol";
import {IBalancerVault, SwapKind, IAsset, BatchSwapStep, FundManagement, JoinPoolRequest} from "../../interfaces/external/balancer/IBalancerVault.sol";
import {IMinter, IGauge} from "./IBalancer.sol";

struct BalancerValues {
    address balMinter;
    bytes32 balPoolId;
    address balVault;
    address gauge;
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
contract BalancerCompounder is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    BalancerValues internal balancerValues;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();
    error Disabled();

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
    ) external initializer {
        BalancerValues memory balancerValues_ = abi.decode(
            strategyInitData_,
            (BalancerValues)
        );

        if (IGauge(balancerValues_.gauge).is_killed()) revert Disabled();

        balancerValues = balancerValues_;

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(asset_).approve(balancerValues_.gauge, type(uint256).max);

        _name = string.concat(
            "VaultCraft BalancerCompounder ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-bc-", IERC20Metadata(asset()).symbol());
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

    function _totalAssets() internal view override returns (uint256) {
        return IGauge(balancerValues.gauge).balanceOf(address(this));
    }

    /// @notice The token rewarded
    function rewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(
        uint256 assets,
        uint256,
        bytes memory
    ) internal virtual override {
        IGauge(balancerValues.gauge).deposit(assets);
    }

    function _protocolWithdraw(
        uint256 assets,
        uint256
    ) internal virtual override {
        IGauge(balancerValues.gauge).withdraw(assets, false);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    function claim() internal override returns (bool success) {
        // Caching
        BalancerValues memory balancerValues_ = balancerValues;

        try IMinter(balancerValues_.balMinter).mint(balancerValues_.gauge) {
            success = true;
        } catch {}
    }

    /**
     * @notice Execute Strategy and take fees.
     */
    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        claim();

        // Caching
        BalancerValues memory balancerValues_ = balancerValues;
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
            if (rewardBal > 0 && rewardBal >= tradePath.minTradeAmount) {
                // Decode since nested struct[] isnt allowed in storage
                BatchSwapStep[] memory swaps = abi.decode(
                    tradePath.swaps,
                    (BatchSwapStep[])
                );
                // Use the actual rewardBal as the amount to sell
                swaps[0].amount = rewardBal;

                // Swap to base asset
                IBalancerVault(balancerValues_.balVault).batchSwap(
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
                balancerValues_.underlyings.length
            );
            // Use the actual base asset balance to pool.
            amounts[harvestValues_.indexIn] = poolAmount;

            // Some pools need to be encoded with a different length array than the actual input amount array
            bytes memory userData;
            if (
                balancerValues_.underlyings.length !=
                harvestValues_.amountsInLen
            ) {
                uint256[] memory amountsIn = new uint256[](
                    harvestValues_.amountsInLen
                );
                amountsIn[harvestValues_.indexInUserData] = poolAmount;
                userData = abi.encode(1, amountsIn, 0); // Exact In Enum, inAmounts, minOut
            } else {
                userData = abi.encode(1, amounts, 0); // Exact In Enum, inAmounts, minOut
            }

            // Pool base asset
            IBalancerVault(balancerValues_.balVault).joinPool(
                balancerValues_.balPoolId,
                address(this),
                address(this),
                JoinPoolRequest(
                    balancerValues_.underlyings,
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
            IERC20(_rewardTokens[0]).approve(balancerValues.balVault, 0);
            unchecked {
                ++i;
            }
        }
        delete _rewardTokens;

        // Add new rewardToken
        for (uint i; i < tradePaths_.length; ) {
            _rewardTokens.push(address(tradePaths_[i].assets[0]));
            IERC20(address(tradePaths_[i].assets[0])).approve(
                balancerValues.balVault,
                type(uint).max
            );
            unchecked {
                ++i;
            }
        }

        // Reset old base asset
        if (harvestValues.baseAsset != address(0)) {
            IERC20(harvestValues.baseAsset).approve(balancerValues.balVault, 0);
        }
        // approve and set new base asset
        IERC20(harvestValues_.baseAsset).approve(
            balancerValues.balVault,
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
