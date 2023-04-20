// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface VaultAPI is IERC20 {
    function deposit(uint256 amount) external returns (uint256);

    function withdraw(
        uint256 maxShares,
        address recipient,
        uint256 maxLoss
    ) external returns (uint256);

    function pricePerShare() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function depositLimit() external view returns (uint256);

    function token() external view returns (address);

    function lastReport() external view returns (uint256);

    function lockedProfit() external view returns (uint256);

    function lockedProfitDegradation() external view returns (uint256);

    function totalDebt() external view returns (uint256);
}

interface IYearnRegistry {
    function latestVault(address token) external view returns (address);
}
