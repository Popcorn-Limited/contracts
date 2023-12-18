// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

interface IGmdVault {
    struct PoolInfo {
        address lpToken;
        address GDlptoken;
        uint256 EarnRateSec;
        uint256 totalStaked;
        uint256 lastUpdate;
        uint256 vaultcap;
        uint256 glpFees;
        uint256 APR;
        bool stakable;
        bool withdrawable;
        bool rewardStart;
    }

    function enter(uint256 _amountIn, uint256 _pId) external;

    function leave(uint256 _share, uint256 _pId) external;

    function GDpriceToStakedtoken(uint256 _pid) external view returns(uint256);

    function poolInfo(uint256 _pId) view external returns (PoolInfo memory);

}
