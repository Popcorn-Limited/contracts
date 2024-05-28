// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IBeefyVault {
    function want() external view returns (address);

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _shares) external;

    function withdrawAll() external;

    function balanceOf(address _account) external view returns (uint256);

    //Returns total balance of underlying token in the vault and its strategies
    function balance() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function earn() external;

    function getPricePerFullShare() external view returns (uint256);

    function strategy() external view returns (address);
}

interface IBeefyStrat {
    function withdrawFee() external view returns (uint256);

    function withdrawalFee() external view returns (uint256);
}
