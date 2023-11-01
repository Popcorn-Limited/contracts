import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

import {AaveV3Depositor} from "../../../src/strategies/aave/AaveV3Depositor.sol";
import {IBaseAdapter, AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";

import {ITestConfigStorage, TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {BaseStrategyTest} from "../../base/BaseStrategyTest.sol";

import {AaveV3TestConfigStorage} from "./AaveV3TestConfigStorage.sol";


contract AaveV3DepositorTest is BaseStrategyTest {
    function setUp() public {
        _setUpBaseTest(0);
    }

    function _deployTestConfigStorage() internal override {
        testConfigStorage = ITestConfigStorage(address(new AaveV3TestConfigStorage()));
    }

    function _setUpStrategy(
        AdapterConfig memory adapterConfig,
        address owner_
    ) internal override returns (IBaseAdapter) {
        address _strategy = Clones.clone(address(new AaveV3Depositor()));

        vm.startPrank(owner_);
        IBaseAdapter(_strategy).initialize(adapterConfig);
        vm.stopPrank();

        return IBaseAdapter(_strategy);
    }

}