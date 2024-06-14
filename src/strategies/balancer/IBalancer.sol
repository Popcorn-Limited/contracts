// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

interface IGauge {
    function lp_token() external view returns (address);

    function bal_token() external view returns (address);

    function is_killed() external view returns (bool);

    function totalSupply() external view returns (uint256);

    function balanceOf(address user) external view returns (uint256);

    function withdraw(uint256 amount, bool _claim_rewards) external;

    function deposit(uint256 amount) external;
}

interface IMinter {
    function mint(address gauge) external;

    function getBalancerToken() external view returns (address);

    function getGaugeController() external view returns (address);
}

interface IController {
    function gauge_exists(address _gauge) external view returns (bool);
}
