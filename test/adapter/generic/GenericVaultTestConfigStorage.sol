import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";

import {TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {BaseTestConfigStorage} from "../../base/BaseTestConfigStorage.sol";
import {AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";

contract GenericVaultTestConfigStorage is BaseTestConfigStorage {
    IERC20[] public rewardTokens;
    // ETH/oETH Balancer LP token
    IERC20 public constant token = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    constructor() {
        _testConfigs.push(TestConfig({
            asset: token,
            depositDelta: 1e16,
            withdrawDelta: 1e16,
            testId: "Generic WETH Sommelier",
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
            underlying: token,
            lpToken: IERC20(address(0)),
            useLpToken: false,
            rewardTokens: rewardTokens,
            owner: msg.sender,
            
            protocolData: abi.encode(0xfd6db5011b171B05E1Ea3b92f9EAcaEEb055e971)
        }));
    }
}