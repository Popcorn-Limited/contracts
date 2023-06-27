// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IVault {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function pool() external view returns (address);

    function currentTick() external view returns (int24);

    function totalSupply() external view returns (uint256);

    function getTotalAmounts() external view returns (uint256, uint256);

    function balanceOf(address _user) external view returns (uint256);

    function withdraw(
        uint256 _amount,
        address _recipient
    ) external returns (uint256, uint256);

    function deposit0Max() external view returns (uint256);

    function deposit1Max() external view returns (uint256);

    function rebalance(
        int24 _baseLower,
        int24 _baseUpper,
        int24 _limitLower,
        int24 _limitUpper,
        int256 swapQuantity
    ) external;

    function baseLower() external view returns (int24);

    function baseUpper() external view returns (int24);

    function limitLower() external view returns (int24);

    function limitUpper() external view returns (int24);

    function owner() external view returns (address);
}

interface IVaultFactory {
    function allVaults(uint256 _pid) external view returns (address);
}

interface IDepositGuard {
    function ICHIVaultFactory() external view returns (address);

    function forwardDepositToICHIVault(
        address _vault,
        address _vaultDeployer,
        address _asset,
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _recipient
    ) external;
}
