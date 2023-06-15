// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IVault {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getTotalAmounts() external view returns (uint256, uint256);

    function balanceOf(address _user) external view returns (uint256);

    function withdraw(
        uint256 _amount,
        address _recipient
    ) external returns (uint256, uint256);

    function deposit0Max() external view returns (uint256);

    function deposit1Max() external view returns (uint256);
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
