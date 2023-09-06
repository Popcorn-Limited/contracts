// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {
    AdapterConfig,
    ProtocolConfig
} from "../BaseAdapter.sol";

interface IBaseAdapter {
    function deposit(uint256 amount) external;

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
