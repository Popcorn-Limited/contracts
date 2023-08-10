// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IOwned} from "../../../interfaces/IOwned.sol";

abstract contract BaseStrategy {
    /// @dev autoHarvest is defined in the strategy but called by the BaseAdapter on each deposit/withdraw
    bool internal autoHarvest;
    /// @dev HarvestData is optionalData for the harvest function
    bytes internal harvestData;
    /// @dev Reward index earned by the strategy
    uint private strategyRewardIndex;
    // vault =>  rewardsIndex
    mapping(address => uint256) public vaultRewardIndex;
    // vault => accruedRewards
    mapping(address => uint256) public accruedVaultRewards;

    function __BaseStrategy_init(
        bool _autoHarvest,
        bytes memory _harvestData
    ) internal {
        autoHarvest = _autoHarvest;
        harvestData = _harvestData;
    }

    /**
     * @notice Claims rewards & executes the strategy
     * @dev harvest should be overriden to receive custom access control depending on each strategy. 
            Some might be purely permissionless others might have access control.
     */
    function harvest(bytes memory optionalData) external virtual {
        uint256 reward = _harvest(optionalData);
        _updateRewardIndex(reward);
    }

    /**
     * @notice Claims rewards & executes the strategy
     */
    function _harvest(bytes memory optionalData) internal virtual {}

    function _updateRewardIndex(uint256 reward) internal {
        //totalAssetDeposited is the total amount of lp tokens or whatever tokens deposited into the strategy
        //reward is shared to all deposits by dividing it by totalAssetDeposited
        //another assumption here is that the reward has been transferred into the strategy already.
        strategyRewardIndex += reward
            .mulDiv(
                uint256(10 ** decimals()),
                totalAssetDeposited(),
                Math.Rounding.Down
            )
            .toUint128();
    }

    /**
     * @notice Updates the reward index of a vault on deposit and withdrawal
     */
    function _accrueVaultReward(address vault) internal {
        uint256 vaultShares = balanceOf[vault];
        uint256 rewardIndexDelta = strategyRewardIndex -
            vaultRewardIndex[vault];
        uint256 rewardEarned = balanceOf(vault).mulDiv(
            rewardIndexDelta,
            uint256(10 ** decimals()),
            Math.Rounding.Down
        );

        accruedVaultRewards[vault] += rewardEarned;
        vaultRewardIndex[vault] = strategyRewardIndex;
    }

    function withdrawAccruedReward() public onlyVault {
        _accrueVaultReward(msg.sender);

        uint256 vaultReward = accruedVaultRewards[msg.sender];
        if (vaultReward > 0) {
            accruedVaultRewards[vault] = 0;
            token.transfer(msg.sender, vaultReward);
        }
    }

    function setAutoHarvest(bool _autoHarvest) external {
        require(
            msg.sender == IOwned(address(this)).owner(),
            "Only the contract owner may perform this action"
        );
        autoHarvest = _autoHarvest;
    }

    function setHarvestData(bytes memory _harvestData) external {
        require(
            msg.sender == IOwned(address(this)).owner(),
            "Only the contract owner may perform this action"
        );
        harvestData = _harvestData;
    }
}
