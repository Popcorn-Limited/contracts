// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../BaseStrategy.sol";
import {IAuraBooster, IAuraRewards} from "./IAura.sol";
import {BaseBalancerLpCompounder, HarvestValues, TradePath} from "../../peripheral/BaseBalancerLpCompounder.sol";

/**
 * @title  Aura Adapter
 * @author amatureApe
 * @notice ERC4626 wrapper for Aura Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/sushiswap/sushiswap/blob/archieve/canary/contracts/Aura.sol.
 * Allows wrapping Aura Vaults.
 */
contract AuraCompounder is BaseStrategy, BaseBalancerLpCompounder {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IAuraBooster public auraBooster;
    IAuraRewards public auraRewards;
    uint256 public auraPoolId;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoDeposit_ Controls if `protocolDeposit` gets called on deposit
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function initialize(address asset_, address owner_, bool autoDeposit_, bytes memory strategyInitData_)
        external
        initializer
    {
        (address auraBooster_, uint256 auraPoolId_) = abi.decode(strategyInitData_, (address, uint256));

        (address balancerLpToken_,,, address auraRewards_,,) = IAuraBooster(auraBooster_).poolInfo(auraPoolId_);

        auraRewards = IAuraRewards(auraRewards_);
        auraBooster = IAuraBooster(auraBooster_);
        auraPoolId = auraPoolId_;

        if (balancerLpToken_ != asset_) revert InvalidAsset();

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(asset_).approve(auraBooster_, type(uint256).max);

        _name = string.concat("VaultCraft Aura ", IERC20Metadata(asset_).name(), " Adapter");
        _symbol = string.concat("vcAu-", IERC20Metadata(asset_).symbol());
    }

    function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _name;
    }

    function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
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

    function _protocolDeposit(uint256 assets, uint256, bytes memory) internal override {
        auraBooster.deposit(auraPoolId, assets, true);
    }

    function _protocolWithdraw(uint256 assets, uint256, bytes memory) internal override {
        auraRewards.withdrawAndUnwrap(assets, false);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim rewards from the aura
    function claim() internal override returns (bool success) {
        try auraRewards.getReward() {
            success = true;
        } catch {}
    }

    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        claim();

        // caching
        address asset_ = asset();

        sellRewardsForLpTokenViaBalancer(asset_, data);

        _protocolDeposit(IERC20(asset_).balanceOf(address(this)), 0, bytes(""));

        emit Harvested();
    }

    function setHarvestValues(
        address newBalancerVault,
        TradePath[] memory newTradePaths,
        HarvestValues memory harvestValues_
    ) external onlyOwner {
        setBalancerLpCompounderValues(newBalancerVault, newTradePaths, harvestValues_);
    }
}
