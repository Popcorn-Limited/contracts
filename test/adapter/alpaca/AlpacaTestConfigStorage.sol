import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";

import {TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {BaseTestConfigStorage} from "../../base/BaseTestConfigStorage.sol";
import {AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";

contract AlpacaTestConfigStorage is BaseTestConfigStorage {
    IERC20 public constant BSC_USD = IERC20(0x55d398326f99059fF775485246999027B3197955);
    IERC20[] public rewardTokens;

    constructor() {
        _testConfigs.push(TestConfig({
            asset: BSC_USD,
            depositDelta: 1,
            withdrawDelta: 1,
            testId: "AlpacaLendV1Depositor ",
            network: "binance",
            blockNumber: 0,
            defaultAmount: 1e18,
            minDeposit: 1e18,
            maxDeposit: 1e18,
            minWithdraw: 1e18,
            maxWithdraw: 1e18,
            optionalData: ""
        }));
        
        _adapterConfigs.push(AdapterConfig({
            underlying: BSC_USD,
            lpToken: IERC20(address(0)) ,
            useLpToken: false,
            rewardTokens: rewardTokens,
            owner: msg.sender,
            protocolData: abi.encode(
                0x158Da805682BdC8ee32d52833aD41E74bb951E59 // AlpacaLendV1 USDT - BSC
            )
        }));
    }
}
