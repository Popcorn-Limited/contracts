// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

struct TestConfig {
    address asset;
    uint256 delta;
    string testId;
    string network;
    uint256 blockNumber;
    uint256 defaultAmount;
    uint256 minDeposit;
    uint256 maxDeposit;
    uint256 minWithdraw;
    uint256 maxWithdraw;
    bytes optionalData;
}

interface ITestConfigStorage {
    function testConfigs(uint256 i) external view returns (TestConfig memory);

    function getTestConfigLength() external view returns (uint256);
}
