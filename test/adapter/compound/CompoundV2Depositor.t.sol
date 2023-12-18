import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

import {CompoundV2Depositor} from "../../../src/strategies/compound/CompoundV2Depositor.sol";
import {IBaseAdapter, AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";

import {ITestConfigStorage, TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {BaseStrategyTest} from "../../base/BaseStrategyTest.sol";

import {CompoundV2TestConfigStorage} from "./CompoundV2TestConfigStorage.sol";


contract CompoundV2DepositorTest is BaseStrategyTest {
    function setUp() public {
        _setUpBaseTest(0);
    }

    function _deployTestConfigStorage() internal override {
        testConfigStorage = ITestConfigStorage(address(new CompoundV2TestConfigStorage()));
    }

    function _setUpStrategy(
        AdapterConfig memory adapterConfig,
        address owner_
    ) internal override returns (IBaseAdapter) {
        address _strategy = Clones.clone(address(new CompoundV2Depositor()));

        vm.startPrank(owner_);
        IBaseAdapter(_strategy).initialize(adapterConfig);
        vm.stopPrank();

        return IBaseAdapter(_strategy);
    }

}