import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";

import {TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {BaseTestConfigStorage} from "../../base/BaseTestConfigStorage.sol";
import {AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";

contract BeefyTestConfigStorage is BaseTestConfigStorage {
    IERC20[] public rewardTokens;
    // wstETH/rETH/sfrxETH Balancer LP token
    IERC20 public constant token = IERC20(0x42ED016F826165C2e5976fe5bC3df540C5aD0Af7);
    constructor() {
        _testConfigs.push(TestConfig({
            asset: token,
            depositDelta: 1e16,
            withdrawDelta: 1e16,
            testId: "Beefy TriCryptoUSDC",
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
            // Beefy wstETH/​rETH/​sfrxETH V3 Vault
            protocolData: abi.encode(0xd4D620B23E91031fa08045b6083878f42558d6b9, address(0))
        }));
    }
}