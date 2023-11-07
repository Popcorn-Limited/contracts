import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";

import {TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {BaseTestConfigStorage} from "../../base/BaseTestConfigStorage.sol";
import {AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";

contract AcrossTestConfigStorage is BaseTestConfigStorage {
    IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20[] public rewardTokens;

    constructor() {
        _testConfigs.push(TestConfig({
            asset: WETH,
            depositDelta: 1,
            withdrawDelta: 1,
            testId: "AaveV3 WETH",
            network: "mainnet",
            blockNumber: 0,
            defaultAmount: 1e18,
            minDeposit: 1e18,
            maxDeposit: 1e18,
            minWithdraw: 1e18,
            maxWithdraw: 1e18,
            optionalData: ""
        }));
        
        _adapterConfigs.push(AdapterConfig({
            underlying: WETH,
            lpToken: IERC20(address(0)) ,
            useLpToken: false,
            rewardTokens: rewardTokens,
            owner: msg.sender,
            protocolData: abi.encode(
                0xc186fA914353c44b2E33eBE05f21846F1048bEda, // Mainnet Across Hop Pool - 0xc186fA914353c44b2E33eBE05f21846F1048bEda
                0x9040e41eF5E8b281535a96D9a48aCb8cfaBD9a48 // Mainnet Across Accelerating Distributor - 0x9040e41eF5E8b281535a96D9a48aCb8cfaBD9a48
            )
        }));
    }
}
