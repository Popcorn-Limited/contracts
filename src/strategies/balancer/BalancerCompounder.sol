// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../BaseStrategy.sol";
import {IMinter, IGauge} from "./IBalancer.sol";
import {BaseBalancerCompounder, BalancerTradeLibrary, IBalancerVault, IAsset, BatchSwapStep, TradePath} from "../../peripheral/BaseCurveCompounder.sol";

struct HarvestValues {
    bytes32 poolId;
    address depositAsset;
    address[] underlyings;
    uint256 amountsInLen;
    uint256 indexIn;
    uint256 indexInUserData;
}

/**
 * @title  Aura Adapter
 * @author amatureApe
 * @notice ERC4626 wrapper for Aura Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/sushiswap/sushiswap/blob/archieve/canary/contracts/Aura.sol.
 * Allows wrapping Aura Vaults.
 */
contract BalancerCompounder is BaseStrategy, BaseBalancerCompounder {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IMinter public minter;
    IGauge public gauge;

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
        (address minter_, address gauge_) = abi.decode(
            strategyInitData_,
            (address, address)
        );

        if (IGauge(gauge_).is_killed()) revert Disabled();

        minter = IMinter(minter_);
        gauge = IGauge(gauge_);

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(asset_).approve(gauge_, type(uint256).max);

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
        return gauge.balanceOf(address(this));
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
        gauge.deposit(assets);
    }

    function _protocolWithdraw(
        uint256 assets,
        uint256
    ) internal virtual override {
        gauge.withdraw(assets, false);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    HarvestValues internal harvestValues;

    error CompoundFailed();

    function claim() internal override returns (bool success) {
        try minter.mint(address(gauge)) {
            success = true;
        } catch {}
    }

    /**
     * @notice Execute Strategy and take fees.
     */
    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        claim();

        sellRewardsViaBalancer();

        // caching
        HarvestValues memory harvestValues_ = harvestValues;

        uint256 amount = IERC20(harvestValues_.depositAsset).balanceOf(address(this));

        BalancerTradeLibrary.addLiquidity(
            balancerVault,
            harvestValues_.poolId,
            harvestValues_.underlyings,
            harvestValues_.amountsInLen,
            harvestValues_.indexIn,
            harvestValues_.indexInUserData,
            amount
        );

        amount = IERC20(asset()).balanceOf(address(this));
        uint256 minOut = abi.decode(data, (uint256));
        if (amount < minOut) revert CompoundFailed();

        _protocolDeposit(amount, 0, bytes(""));

        emit Harvested();
    }

    function setHarvestValues(
        address newBalancerVault,
        TradePath[] memory newTradePaths,
        HarvestValues memory harvestValues_
    ) external onlyOwner {
        setBalancerTradeValues();

        // Reset old base asset
        if (harvestValues.depositAsset != address(0)) {
            IERC20(harvestValues.depositAsset).approve(
                address(balancerVault),
                0
            );
        }
        // approve and set new base asset
        IERC20(harvestValues_.depositAsset).approve(
            newBalancerVault,
            type(uint).max
        );

        harvestValues = harvestValues_;
    }
}
