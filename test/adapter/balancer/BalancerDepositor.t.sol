import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

import {BalancerDepositor} from "../../../src/strategies/balancer/BalancerDepositor.sol";
import {IBaseAdapter, AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";

import {ITestConfigStorage, TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {BaseStrategyTest} from "../../base/BaseStrategyTest.sol";

import {BalancerTestConfigStorage} from "./BalancerTestConfigStorage.sol";


contract BalancerDepositorTest is BaseStrategyTest {
    function setUp() public {
        _setUpBaseTest(0);
    }

    function _deployTestConfigStorage() internal override {
        testConfigStorage = ITestConfigStorage(address(new BalancerTestConfigStorage()));
    }

    function _setUpStrategy(
        AdapterConfig memory adapterConfig,
        address owner_
    ) internal override returns (IBaseAdapter) {
        address _strategy = Clones.clone(address(new BalancerDepositor()));

        vm.startPrank(owner_);
        IBaseAdapter(_strategy).initialize(adapterConfig);
        vm.stopPrank();

        return IBaseAdapter(_strategy);
    }

}