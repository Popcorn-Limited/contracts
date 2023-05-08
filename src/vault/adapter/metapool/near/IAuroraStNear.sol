// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IAuroraStNear {
    function wNear() external view returns (address);

    function stNear() external view returns (address);

    function stNearPrice() external view returns (uint256);

    function wNearSwapFee() external view returns (uint16);

    function stNearSwapFee() external view returns (uint16);

    function swapwNEARForstNEAR(uint256 amount) external;

    function swapstNEARForwNEAR(uint256 amount) external;
}
