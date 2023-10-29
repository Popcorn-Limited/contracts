// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage, TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {IERC20, IBaseAdapter, AdapterConfig} from "../../base/BaseStrategyTest.sol";

contract RocketpoolTestConfigStorage is ITestConfigStorage {
    TestConfig[] public _testConfigs;
    AdapterConfig[] public adapterConfigs;

    IERC20 public constant WETH =
        IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IERC20[] public rewardTokens;

    constructor() {
        // Config 0
        _testConfigs.push(
            TestConfig({
                asset: WETH,
                depositDelta: 500000000000010, // DepositFee + 10
                withdrawDelta: 500000000000010, // Slippage + 10
                testId: "RocketPool WETH",
                network: "mainnet",
                blockNumber: 18104376,
                defaultAmount: 1e18,
                minDeposit: 1e18,
                maxDeposit: 1e18,
                minWithdraw: 1e18,
                maxWithdraw: 1e18,
                optionalData: ""
            })
        );
        adapterConfigs.push(
            AdapterConfig({
                underlying: WETH,
                lpToken: IERC20(address(0)),
                useLpToken: false,
                rewardTokens: rewardTokens,
                owner: address(0x7777),
                protocolData: ""
            })
        );
    }

    function getTestConfigLength() public view returns (uint256) {
        return _testConfigs.length;
    }

    function getTestConfig(
        uint256 i
    ) public view returns (TestConfig memory) {
        if(i > _testConfigs.length) i = 0;
        return _testConfigs[i];
    }

    function getAdapterConfig(
        uint256 i
    ) public view returns (AdapterConfig memory) {
        if(i > adapterConfigs.length) i = 0;
        return adapterConfigs[i];
    }
}
