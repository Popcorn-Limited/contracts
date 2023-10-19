pragma solidity 0.8.19;
import {IBaseAdapter} from "./interfaces/IBaseAdapter.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";



/// @notice The whole reward and accrual logic is heavily based on the Fei Protocol's Flywheel contracts.
/// https://github.com/fei-protocol/flywheel-v2/blob/main/src/rewards/FlywheelStaticRewards.sol
/// https://github.com/fei-protocol/flywheel-v2/blob/main/src/FlywheelCore.sol
struct RewardInfo {
    /// @notice The strategy's last updated index
    uint128 index;
    /// @notice The timestamp the index was last updated at
    uint128 lastUpdatedTimestamp;
}

abstract contract BaseVaultRewardClaimer {

    using Math for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    // rewardToken -> RewardInfo
    mapping(IERC20 => RewardInfo) public rewardInfos;
    // user => rewardToken -> rewardsIndex
    mapping(address => mapping(IERC20 => uint256)) public userIndex;
    // user => rewardToken -> accruedRewards
    mapping(address => mapping(IERC20 => uint256)) public accruedRewards;

    function accrueRewards(IERC20 rewardToken, uint accrued) public {
        // we allow anybody to call this. To prevent someone from accruing rewards that are never
        // sent to the contract, we always transfer them ourselves. Primarily it will be called by a
        // strategy contract reporting its harvest.

        uint supplyTokens = __totalSupply();
        uint128 deltaIndex; // DeltaIndex is the amount of rewardsToken paid out per stakeToken
        if (supplyTokens != 0)
            deltaIndex = accrued
                .mulDiv(
                uint256(10 ** _stakedAssetDecimals()),
                supplyTokens,
                Math.Rounding.Down
            ).toUint128();
        // rewardDecimals * stakeDecimals / stakeDecimals = rewardDecimals
        // 1e18 * 1e6 / 10e6 = 0.1e18 | 1e6 * 1e18 / 10e18 = 0.1e6

        rewardInfos[rewardToken].index += deltaIndex;
        rewardInfos[rewardToken].lastUpdatedTimestamp = block
            .timestamp
            .toUint128();

        rewardToken.safeTransferFrom(msg.sender, address(this), accrued);
    }

    function _accrueUser(address _user) internal {
        address[] memory strategies = _getStrategies();
        uint len = strategies.length;
        for (uint i; i < len; ) {
            IERC20Upgradeable[] memory _tokens = IBaseAdapter(strategies[i]).getRewardTokens();
            for (uint j; j < _tokens.length; ) {
                IERC20 _rewardToken = IERC20(address(_tokens[j]));
                RewardInfo memory rewards = rewardInfos[_rewardToken];
                uint256 oldIndex = userIndex[_user][_rewardToken];

                // user is already up to date.
                if (oldIndex == rewards.index) continue;

                // If user hasn't yet accrued rewards, grant them interest from the strategy beginning if they have a balance
                // Zero balances will have no effect other than syncing to global index
                if (oldIndex == 0) {
                    oldIndex =
                        10 ** IERC20Metadata(address(_rewardToken)).decimals();
                }

                uint256 deltaIndex = rewards.index - oldIndex;

                // Accumulate rewards by multiplying user tokens by rewardsPerToken index and adding on unclaimed
                uint256 supplierDelta = _balanceOf(_user).mulDiv(
                    deltaIndex,
                    uint256(10 ** _stakedAssetDecimals()),
                    Math.Rounding.Down
                );
                // stakeDecimals  * rewardDecimals / stakeDecimals = rewardDecimals
                // 1e18 * 1e6 / 10e18 = 0.1e18 | 1e6 * 1e18 / 10e18 = 0.1e6

                userIndex[_user][_rewardToken] = rewards.index;
                accruedRewards[_user][_rewardToken] += supplierDelta;

                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    function _getStrategies() internal virtual returns(address[] memory);

    function _stakedAssetDecimals() internal virtual returns(uint256);

    function __totalSupply() internal view returns(uint256) {
        return 1e18;
    }

    function _balanceOf(address vault) internal view returns(uint256) {
        return 5e18;
    }

}
