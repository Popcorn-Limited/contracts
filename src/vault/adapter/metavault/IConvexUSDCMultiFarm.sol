// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IStrategy} from "../../../interfaces/vault/IStrategy.sol";

interface IConvexUSDCMultiFarm is IStrategy {
    struct ProtocolAddress {
        address addr;
        bytes desc;
    }

    struct ProtocolUint {
        uint256 num;
        bytes desc;
    }

    function getProtocolAddress(
        uint256 _idx
    ) external view returns (ProtocolAddress memory);

    function getProtocolUint(
        uint256 _idx
    ) external view returns (ProtocolUint memory);
}

interface IConvexBooster {
    function deposit(uint256 pid, uint256 amount, bool stake) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function poolInfo(
        uint256 pid
    )
        external
        view
        returns (
            address lpToken,
            address token,
            address gauge,
            address crvRewards,
            address stash,
            bool shutdown
        );
}

interface IConvexRewards {
    function withdrawAndUnwrap(
        uint256 amount,
        bool claim
    ) external returns (bool);

    function getReward(
        address _account,
        bool _claimExtras
    ) external returns (bool);

    function balanceOf(address addr) external view returns (uint256);

    function stakingToken() external view returns (address);

    function extraRewards(uint256 index) external view returns (IRewards);

    function extraRewardsLength() external view returns (uint256);

    function rewardToken() external view returns (address);
}

interface IRewards {
    function rewardToken() external view returns (address);
}

interface ICurveGauge {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;
}
