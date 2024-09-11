// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";

interface IMaticXPool {
    function convertMaticToMaticX(uint256 maticAmount)
        external 
        view 
        returns (uint256 maticXAmount, uint256 maticReserve, uint256 maticXReserve);
    
    function convertMaticXToMatic(uint256 maticXAmount)
        external 
        view 
        returns (uint256 maticAmount, uint256 maticReserve, uint256 maticXReserve);


    function swapMaticForMaticXViaInstantPool() external payable;

    function swapMaticXForMaticViaInstantPool(uint256 maticXAmount) external;
}