import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

import {BeefyDepositor} from "../../../src/strategies/beefy/BeefyDepositor.sol";
import {IBaseAdapter, AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";

import {ITestConfigStorage, TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {BaseStrategyTest} from "../../base/BaseStrategyTest.sol";

import {BeefyTestConfigStorage} from "./BeefyTestConfigStorage.sol";


contract BeefyDepositorTest is BaseStrategyTest {
    function setUp() public {
        _setUpBaseTest(0);
    }

    function _deployTestConfigStorage() internal override {
        testConfigStorage = ITestConfigStorage(address(new BeefyTestConfigStorage()));
    }

    function _setUpStrategy(
        AdapterConfig memory adapterConfig,
        address owner_
    ) internal override returns (IBaseAdapter) {
        address _strategy = Clones.clone(address(new BeefyDepositor()));

        vm.startPrank(owner_);
        vm.label(_strategy, "BeefyDepositor");
        IBaseAdapter(_strategy).initialize(adapterConfig);
        vm.stopPrank();

        return IBaseAdapter(_strategy);
    }

}