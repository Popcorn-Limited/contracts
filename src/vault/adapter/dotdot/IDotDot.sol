// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;


interface IDotDotStaking {

    function deposit(address _user, address _token, uint256 _amount) external;

    function withdraw(address _receiver, address _token, uint256 _amount) external;

    function claim(address _user, address[] calldata _tokens, uint256 _maxBondAmount) external;

    function userBalances(address user, address pool) external view returns (uint256);

    function extraRewards(address pool) external view returns (address[] memory);

    function DDD() external view returns (address);
    function EPX() external view returns (address);

    function depositTokens(address _token) external view returns (address);

}