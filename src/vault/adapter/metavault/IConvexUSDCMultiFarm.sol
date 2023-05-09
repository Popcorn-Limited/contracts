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

interface ICurvePool {
    function add_liquidity(
        uint256[] memory _depositAmounts,
        uint256 _min_mint_amount
    ) external;

    function remove_liquidity_one_coin(
        uint256 _burn_amount,
        int128 _idx,
        uint256 _min_received
    ) external;

    function get_balances() external view returns (uint256[] memory _balances);

    function coins(uint256 _idx) external view returns (address _coin);

    function approve(address _spender, uint256 _value) external;
}
