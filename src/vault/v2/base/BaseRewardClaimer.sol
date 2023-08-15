// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import "./BaseHelper.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract BaseRewardClaimer is BaseHelper {
    using Math for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    // rewardToken -> rewardIndex
    mapping(IERC20 => uint256) public strategyRewardIndex;
    // vault => rewardToken -> rewardsIndex
    mapping(address => mapping(IERC20 => uint256)) public vaultRewardIndex;
    // vault => rewardToken -> accruedRewards
    mapping(address => mapping(IERC20 => uint256)) public accruedVaultRewards;

    function _accrueStrategyReward(IERC20 rewardToken, uint256 reward) internal {
        //todo: this function has to be triggered by the reward holder
        //totalAssetDeposited is the total amount of lp tokens or whatever tokens deposited into the strategy
        //reward is shared to all deposits by dividing it by totalAssetDeposited
        //another assumption here is that the reward has been transferred into the strategy already.
        uint totalAssetDeposited = totalAssets();
        uint256 rewardIndex;

        if(totalAssetDeposited != 0) {
            rewardIndex = reward.mulDiv(
                uint256(10 ** decimals()),
                totalAssetDeposited,
                Math.Rounding.Down
            ).toUint128();
        }

        strategyRewardIndex[rewardToken] += rewardIndex;
        rewardToken.safeTransferFrom(msg.sender, address(this), reward);
    }

    /**
     * @notice Updates the reward index of a vault on deposit and withdrawal
     */
    function _accrueVaultReward(address vault) internal {
        address[] memory _tokens = getRewardTokens();

        for (uint i; i < _tokens.length; ) {
            IERC20 _rewardToken = IERC20(_tokens[i]);
            uint256 rewardIndexDelta =
                strategyRewardIndex[_rewardToken] - vaultRewardIndex[vault][_rewardToken];
            if (rewardIndexDelta == 0) continue;

            uint256 rewardEarned = balanceOf(vault).mulDiv(
                rewardIndexDelta,
                uint256(10 ** decimals()),
                Math.Rounding.Down
            );

            accruedVaultRewards[vault][_rewardToken] += rewardEarned;
            vaultRewardIndex[vault][_rewardToken] = strategyRewardIndex[_rewardToken];

            unchecked {++i;}
        }
    }

    function withdrawAccruedReward() public {
        _accrueVaultReward(msg.sender);
        address[] memory _tokens = getRewardTokens();

        for (uint i; i < _tokens.length; ) {
            IERC20 _rewardToken = IERC20(_tokens[i]);
            uint256 vaultReward = accruedVaultRewards[msg.sender][_rewardToken];

            if(vaultReward > 0){
                accruedVaultRewards[msg.sender][_rewardToken] = 0;
                _rewardToken.transfer(msg.sender, vaultReward);
            }

            unchecked {++i;}
        }
    }
}
