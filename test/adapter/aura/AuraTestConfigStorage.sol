import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";

import {TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {BaseTestConfigStorage} from "../../base/BaseTestConfigStorage.sol";
import {AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";

contract AuraTestConfigStorage is BaseTestConfigStorage {
    IERC20[] public rewardTokens;
    // rETH/WETH Balancer Pool LP Token
    IERC20 public constant token = IERC20(0x1E19CF2D73a72Ef1332C882F20534B6519Be0276);
    constructor() {
        _testConfigs.push(TestConfig({
            asset: token,
            depositDelta: 0,
            withdrawDelta: 0,
            testId: "Aura rETH/WETH",
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
            underlying: IERC20(address(0)),
            lpToken: token,
            useLpToken: true,
            rewardTokens: rewardTokens,
            owner: msg.sender,
            protocolData: abi.encode(109)
        }));
    }
}