import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

import {GenericVaultDepositor} from "../../../src/strategies/generic/GenericVaultDepositor.sol";
import {IBaseAdapter, AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";

import {ITestConfigStorage, TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {BaseStrategyTest} from "../../base/BaseStrategyTest.sol";

import {GenericVaultTestConfigStorage} from "./GenericVaultTestConfigStorage.sol";


contract GenericVaultDepositorTest is BaseStrategyTest {
    function setUp() public {
        _setUpBaseTest(0);
    }

    function _deployTestConfigStorage() internal override {
        testConfigStorage = ITestConfigStorage(address(new GenericVaultTestConfigStorage()));
    }

    function _setUpStrategy(
        AdapterConfig memory adapterConfig,
        address owner_
    ) internal override returns (IBaseAdapter) {
        address _strategy = Clones.clone(address(new GenericVaultDepositor()));

        vm.startPrank(owner_);
        vm.label(_strategy, "GenericVaultDepositor");
        IBaseAdapter(_strategy).initialize(adapterConfig);
        vm.stopPrank();

        return IBaseAdapter(_strategy);
    }
}