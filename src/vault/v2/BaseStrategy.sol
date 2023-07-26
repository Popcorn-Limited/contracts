pragma solidity ^0.8.15;

import {BaseVault, BaseVaultInitData} from "./BaseVault.sol";

abstract contract BaseStrategy is BaseVault {
    uint128 public lastHarvest;
    uint128 public harvestCooldown;
    uint8 public autoHarvest;

    event HarvestCooldownChanged(uint256 oldCooldown, uint256 newCooldown);

    error InvalidHarvestCooldown(uint256 cooldown);
    error NotStrategy(address sender);

    function __BaseStrategy__init(uint128 _harvestCooldown, uint8 _autoHarvest) internal onlyInitializing {
        lastHarvest = uint128(block.timestamp);
        autoHarvest = _autoHarvest;
        harvestCooldown = _harvestCooldown; 
    }

    function _afterDeposit() internal virtual override {
        if (autoHarvest == 2 && lastHarvest + harvestCooldown < block.timestamp) {
            harvest();
        }
    }

    function _afterWithdrawal() internal virtual override {
        if (autoHarvest == 2 && lastHarvest + harvestCooldown < block.timestamp) {
            harvest();
        }
    }

        /**
     * @notice Set a new harvestCooldown for this adapter. Caller must be owner.
     * @param newCooldown Time in seconds that must pass before a harvest can be called again.
     * @dev Cant be longer than 1 day.
     */
     function setHarvestCooldown(uint128 newCooldown) external onlyOwner {
        // Dont wait more than X seconds
        if (newCooldown >= 1 days) revert InvalidHarvestCooldown(newCooldown);

        emit HarvestCooldownChanged(harvestCooldown, newCooldown);

        harvestCooldown = newCooldown;
    }

    event AutoHarvestToggled(uint oldValue, uint newValue);

    function toggleAutoHarvest() external onlyOwner {
        uint256 _autoHarvest = autoHarvest;
        /// @dev using 1 & 2 instead of 0 & 1 saves gas.
        if (_autoHarvest == 1) {
            emit AutoHarvestToggled(1, 2);
            autoHarvest = 2;
        } else {
            emit AutoHarvestToggled(2, 1);
            autoHarvest = 1;
        }
    }

    event Harvest();

    function harvest() public virtual;


    // @dev Exists for compatibility for flywheel systems.
    function claimRewards() external {
        harvest();
    }

    /**
     * @notice Allows the strategy to deposit assets into the underlying protocol without minting new adapter shares.
     * @dev This can be used e.g. for a compounding strategy to increase the value of each adapter share.
     */
    function strategyDeposit(uint256 amount, uint256 shares) internal {
        _protocolDeposit(amount, shares);
    }

    /**
     * @notice Allows the strategy to withdraw assets from the underlying protocol without burning adapter shares.
     * @dev This can be used e.g. for a leverage strategy to reduce leverage without the need for the strategy to hold any adapter shares.
     */
    function strategyWithdraw(uint256 amount, uint256 shares) internal {
        _protocolWithdraw(amount, shares);
    }
}
