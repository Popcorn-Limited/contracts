// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IGauge {
    function stake() external view returns (address);

    function balanceOf(address _user) external view returns (uint256);

    function deposit(uint256 _amount, uint256 _tokenId) external;

    function withdraw(uint256 _amount) external;

    function getReward(address _account, address[] memory _tokens) external;

    function rewards(uint256 _index) external view returns (address);
}

interface ILpToken {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function stable() external view returns (bool);
}
