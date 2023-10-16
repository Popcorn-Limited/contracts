// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IMasterChefV2 {
    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of SUSHI entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each MCV2 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of SUSHI to distribute per block.
    struct PoolInfo {
        uint128 accSushiPerShare;
        uint64 lastRewardBlock;
        uint64 allocPoint;
    }

    function poolInfo(
        uint256 pid
    ) external view returns (IMasterChefV2.PoolInfo memory);

    function userInfo(
        uint256 pid,
        address adapterAddress
    ) external view returns (IMasterChefV2.UserInfo memory);

    function lpToken(uint256 pid) external view returns (address);

    function rewarder(uint256 pid) external view returns (address);

    function totalAllocPoint() external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount, address _to) external;

    function withdraw(uint256 _pid, uint256 _amount, address _to) external;

    function harvest(uint256 _pid, address _to) external;

    function pendingSushi(
        uint256 _pid,
        address _user
    ) external view returns (uint256);
}

interface IRewarder {
    function rewardToken() external view returns (address);
}
