// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";

interface IIonPool is IERC20 {
    function supply(address user, uint256 amount, bytes32[] memory proof) external;

    function withdraw(address receiver, uint256 amount) external;

    function updateSupplyCap(uint256 amount) external;

    function underlying() external view returns (address);
}

interface IWhitelist {
    function updateLendersRoot(bytes32 _lendersRoot) external;
}
