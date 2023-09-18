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

    function pause() external;

    function unpause() external;

    function addVault(address vault) external;

    function deposit(uint256 amount) external;

    function isVault(address vault) external view returns (bool);

    function withdraw(uint256 amount, address receiver) external;

    function totalAssets() external view returns (uint256);

    function rewardTokens() external view returns (address[] memory);

    function underlying() external view returns (address);

    function lpToken() external view returns (address);

    function useLpToken() external view returns (bool);

    function maxDeposit() external view virtual returns (uint256);

    function maxWithdraw() external view virtual returns (uint256);

    function initialize(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) external;
}
