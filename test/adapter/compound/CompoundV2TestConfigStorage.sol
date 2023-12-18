import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";

import {TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {BaseTestConfigStorage} from "../../base/BaseTestConfigStorage.sol";
import {AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";

contract CompoundV2TestConfigStorage is BaseTestConfigStorage {
    IERC20[] public rewardTokens;
    // DAI
    IERC20 public constant token = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    constructor() {
        _testConfigs.push(TestConfig({
            asset: token,
            depositDelta: 1e10,
            withdrawDelta: 1e10,
            testId: "Compound V2 DAI",
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
            // cDAI address
            protocolData: abi.encode(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643)
        }));
    }
}