// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage, TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {IERC20, IBaseAdapter, AdapterConfig} from "../../base/BaseStrategyTest.sol";
import {BaseTestConfigStorage} from "../../base/BaseTestConfigStorage.sol";

contract RocketpoolTestConfigStorage is BaseTestConfigStorage {
    IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

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
                // TODO: defaultAmount, minDeposit, etc. seem to be pointless parameters.
                // It's a waste to put these values here. Just define them in the test function itself
                defaultAmount: 1e18,
                minDeposit: 1e18,
                maxDeposit: 1e18,
                minWithdraw: 1e18,
                maxWithdraw: 1e18,
                optionalData: ""
            })
        );
        _adapterConfigs.push(
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
}
