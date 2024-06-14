// SPDX-FileCopyrightText: 2020 Lido <info@lido.fi>

// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";

// @dev router contract
interface IIndexUtils {
    function addLPAndStake(
        address _indexFund, 
        uint256 _amountIdxTokens,
        address _pairedLpTokenProvided,
        uint256 _amtPairedLpTokenProvided,
        uint256 _amountPairedLpTokenMin,
        uint256 _slippage,
        uint256 _deadline
    ) external;

    function unstakeAndRemoveLP(
        address _indexFund, 
        uint256 _amountStakedTokens,
        uint256 _minLPTokens,
        uint256 _minPairedLpToken,
        uint256 _deadline
    ) external;
}

interface IIndexToken {
    function indexTokens(uint256 index) external view returns(
        address token,
        uint256 weighting,
        uint256 basePriceUSDX96,
        uint256 c1,
        uint256 q1
    ); 
}

interface ICamelotLPToken {
    function addLiquidityV2(uint256 _idxLPTokens,uint256 _pairedLPTokens,uint256 _slippage,uint256 _deadline) external;
}

interface ITokenPod {
    // unwraps pod-token into its underlying
    // _token: underlying address
    // _amount: amount of pod-token to unwrap
    // _percentage: 100
    function debond(uint256 _amount,address[] memory _token,uint8[] memory _percentage) external;
}

interface IStakedToken {
    // returns the address of the camelotLP token staked
    function stakingToken() external view returns (address lpToken);

    // returns the address of the pool to claim rewards
    function poolRewards() external view returns (address poolReward);

    // stakes LP token for rewards. output amount is 1:1 
    function stake(address user, uint256 amount) external;

    // unstakes and receives LP token, 1:1
    function unstake(uint256 amount) external;
    
}

interface IPoolRewards {
    // returns token address
    function rewardsToken() external view returns (address);

    function claimReward(address wallet) external;

    function shares(address who) external view returns (uint256);
}

interface IPeapods {
    function totalSupply() external view returns (uint256);

    function getTotalShares() external view returns (uint256);

    function asset() external view returns (address);

    function initialize(bytes memory adapterInitData, address _wethAddress, bytes memory lidoInitData) external;
}