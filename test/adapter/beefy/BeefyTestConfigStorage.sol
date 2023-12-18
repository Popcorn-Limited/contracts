import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";

import {TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {BaseTestConfigStorage} from "../../base/BaseTestConfigStorage.sol";
import {AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";

contract BeefyTestConfigStorage is BaseTestConfigStorage {
    IERC20[] public rewardTokens;
    // ETH/oETH Balancer LP token
    IERC20 public constant token = IERC20(0x94B17476A93b3262d87B9a326965D1E91f9c13E7);
    constructor() {
        _testConfigs.push(TestConfig({
            asset: token,
            depositDelta: 1e16,
            withdrawDelta: 1e16,
            testId: "Beefy ETH LP",
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
            // Beefy ETH/oETH Balancer LP Vault
            protocolData: abi.encode(0x31C0dac4c896cb84adFEF2F8e41cb9295EEc93c2, address(0))
        }));
    }
}