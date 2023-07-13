pragma solidity ^0.8.15;

import {BaseVault, BaseVaultInitData} from "./BaseVault.sol";

abstract contract VaultWithStrategy is BaseVault {
    uint256 public lastHarvest;
    uint256 public autoHarvest; // using a bool will cost more gas since we can't pack it
    uint256 public harvestCooldown;

    event HarvestCooldownChanged(uint256 oldCooldown, uint256 newCooldown);

    error InvalidHarvestCooldown(uint256 cooldown);
    error NotStrategy(address sender);

    modifier onlyStrategy() {
        if (msg.sender != address(this)) revert NotStrategy(msg.sender);
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function __VaultWithStrategy__init(BaseVaultInitData memory initData, uint _autoHarvest, uint _harvestCooldown)
        internal 
        onlyInitializing
    {
        __BaseVault__init(initData);

        lastHarvest = block.timestamp;
        autoHarvest = _autoHarvest;
        harvestCooldown = _harvestCooldown;
    }

    function _afterDeposit() internal virtual override {
        if (autoHarvest == 1 && lastHarvest + harvestCooldown < block.timestamp) {
            harvest();
        }
    }

    function _afterWithdrawal() internal virtual override {
        if (autoHarvest == 1 && lastHarvest + harvestCooldown < block.timestamp) {
            harvest();
        }
    }

    /**
     * @notice Set a new harvestCooldown for this adapter. Caller must be owner.
     * @param newCooldown Time in seconds that must pass before a harvest can be called again.
     * @dev Cant be longer than 1 day.
     */
    function setHarvestCooldown(uint256 newCooldown) external onlyOwner {
        // Dont wait more than X seconds
        if (newCooldown >= 1 days) revert InvalidHarvestCooldown(newCooldown);

        emit HarvestCooldownChanged(harvestCooldown, newCooldown);

        harvestCooldown = newCooldown;
    }

    event AutoHarvestToggled(uint oldValue, uint newValue);

    function toggleAutoHarvest() external onlyOwner {
        uint256 _autoHarvest = autoHarvest;
        emit AutoHarvestToggled(_autoHarvest, (_autoHarvest + 1) % 2);
        // (0 + 1) % 2 = 1
        // (1 + 1) % 2 = 0
        autoHarvest = (_autoHarvest + 1) % 2;
    }

    event Harvest();

    function harvest() public virtual;

    function rewardTokens() public view virtual returns (address[] memory);

    // @dev Exists for compatibility for flywheel systems.
    function claimRewards() external {
        harvest();
    }

    /**
     * @notice Allows the strategy to deposit assets into the underlying protocol without minting new adapter shares.
     * @dev This can be used e.g. for a compounding strategy to increase the value of each adapter share.
     */
    function strategyDeposit(uint256 amount, uint256 shares) public onlyStrategy {
        _protocolDeposit(amount, shares);
    }

    /**
     * @notice Allows the strategy to withdraw assets from the underlying protocol without burning adapter shares.
     * @dev This can be used e.g. for a leverage strategy to reduce leverage without the need for the strategy to hold any adapter shares.
     */
    function strategyWithdraw(uint256 amount, uint256 shares) public onlyStrategy {
        _protocolWithdraw(amount, shares);
    }
}
