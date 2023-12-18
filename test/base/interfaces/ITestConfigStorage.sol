// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";

struct TestConfig {
    IERC20 asset;
    uint256 depositDelta; // TODO -- should we add deposit / withdraw delta?
    uint256 withdrawDelta; // TODO -- should we add deposit / withdraw delta?
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
    function getTestConfig(uint256 i) external view returns (TestConfig memory);
    function getTestConfigLength() external view returns (uint256);
    function getAdapterConfig(uint256 i) external view returns (AdapterConfig memory);
    function getAdapterConfigLength() external view returns (uint);
}
