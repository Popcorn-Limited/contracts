// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

struct AdapterConfig {
    IERC20 underlying;
    IERC20 lpToken;
    bool useLpToken;
    IERC20[] rewardTokens;
    address owner;
}

struct ProtocolConfig {
    address registry;
    bytes protocolInitData;
}

interface IBaseAdapter {
    function deposit(uint256 amount) external;

    function withdraw(uint256 amount, address receiver) external;

    function totalAssets() external view returns (uint256);

    function maxDeposit() external view virtual returns (uint256);

    function maxWithdraw() external view virtual returns (uint256);

    function underlying() external view returns (address);

    function lpToken() external view returns (address);

    function useLpToken() external view returns (bool);

    function pause() external;

    function unpause() external;

    function addVault(address vault) external;

    function isVault(address vault) external view returns (bool);

    function rewardTokens() external view returns (IERC20[] memory);

    function setRewardsToken(IERC20[] memory rewardTokens) external;

    function initialize(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) external;
}
