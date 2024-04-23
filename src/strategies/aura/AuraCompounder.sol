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

struct TradePath {
    uint256[] amount;
    uint256[] assetInIndex;
    uint256[] assetOutIndex;
    address[] assets;
    int256[] limits;
    uint256 minTradeAmount;
    bytes32[] poolId;
    bytes[] userData;
}

// struct TradePath {
//     address[] assets;
//     int256[] limits;
//     uint256 minTradeAmount;
//     BatchSwapStep[] swaps;
// }

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
        IAuraBooster(auraValues.auraBooster).deposit(
            auraValues.pid,
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
     * @dev Delegatecall to strategy's harvest() function. All necessary data is passed via `strategyConfig`.
     * @dev Delegatecall is used to in case any logic requires the adapters address as a msg.sender. (e.g. Synthetix staking)
     */
    function harvest() public override takeFees {
        claim();

        // Trade to base asset
        // uint256 len = _rewardTokens.length;
        // for (uint256 i = 0; i < len; i++) {
        //     uint256 rewardBal = IERC20(_rewardTokens[i]).balanceOf(
        //         address(this)
        //     );
        //     if (rewardBal >= tradePaths[i].minTradeAmount) {
        //         tradePaths[i].swaps[0].amount = rewardBal;

        //         IAsset[] memory balAssets = new IAsset[](
        //             tradePaths[i].assets.length
        //         );

        //         IBalancerVault(auraValues.balVault).batchSwap(
        //             SwapKind.GIVEN_IN,
        //             tradePaths[i].swaps,
        //             balAssets,
        //             FundManagement(
        //                 address(this),
        //                 false,
        //                 payable(address(this)),
        //                 false
        //             ),
        //             tradePaths[i].limits,
        //             block.timestamp
        //         );
        //     }
        // }
        // uint256 poolAmount = IERC20(harvestValues.baseAsset).balanceOf(
        //     address(this)
        // );
        // if (poolAmount > 0) {
        //     uint256[] memory amounts = new uint256[](
        //         auraValues.underlyings.length
        //     );
        //     amounts[harvestValues.indexIn] = poolAmount;

        //     bytes memory userData;
        //     if (auraValues.underlyings.length != harvestValues.amountsInLen) {
        //         uint256[] memory amountsIn = new uint256[](
        //             harvestValues.amountsInLen
        //         );
        //         amountsIn[harvestValues.indexInUserData] = poolAmount;
        //         userData = abi.encode(1, amountsIn, 0); // Exact In Enum, inAmounts, minOut
        //     } else {
        //         userData = abi.encode(1, amounts, 0); // Exact In Enum, inAmounts, minOut
        //     }

        //     // Pool base asset
        //     IBalancerVault(auraValues.balVault).joinPool(
        //         auraValues.balPoolId,
        //         address(this),
        //         address(this),
        //         JoinPoolRequest(
        //             auraValues.underlyings,
        //             amounts,
        //             userData,
        //             false
        //         )
        //     );

        //     // redeposit
        //     _protocolDeposit(IERC20(asset()).balanceOf(address(this)), 0);
        // }

        emit Harvested();
    }

    // mapping(address => BatchSwapStep[]) internal swaps;
    // mapping(address => IAsset[]) internal assets;
    // mapping(address => int256[]) internal limits;
    // uint256[] internal minTradeAmounts;
    // IERC20 internal baseAsset;
    // uint256 internal indexIn;
    // uint256 internal indexInUserData;
    // uint256 internal amountsInLen;

    HarvestValues internal harvestValues;
    TradePath[] internal tradePaths;
    address[] internal _rewardTokens;

    function setHarvestValues(
        HarvestValues memory harvestValues_,
        TradePath[] memory tradePaths_
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
            _rewardTokens.push(tradePaths_[i].assets[0]);
            IERC20(tradePaths_[i].assets[0]).approve(
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
        // for (uint i; i < tradePaths_.length; ) {
        //     tradePaths.push();
        //     tradePaths[i] = tradePaths_[i];
        // }
        // tradePaths = tradePaths_;
    }

    // function _setTradeData(
    //     BatchSwapStep[] memory swaps_,
    //     IAsset[] memory assets_,
    //     int256[] memory limits_
    // ) internal {
    //     address key = address(assets_[0]);
    //     delete swaps[key];

    //     uint256 len = swaps_.length;
    //     for (uint256 i; i < len; i++) {
    //         swaps[key].push(swaps_[i]);
    //     }

    //     limits[key] = limits_;
    //     assets[key] = assets_;
    // }
}
