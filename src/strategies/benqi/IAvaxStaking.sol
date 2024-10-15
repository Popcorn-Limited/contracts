// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";

interface IAvaxStaking {
    // send avax receive sAVAX
    function submit() external payable returns (uint256 sAvaxAmount);

    // avax to sAvax
    function getSharesByPooledAvax(uint256 avaxAmount) external view returns (uint256 sAvaxAmount);

    // sAvax to avax
    function getPooledAvaxByShares(uint256 sAvaxAmount) external view returns (uint256 avaxAmount);
}