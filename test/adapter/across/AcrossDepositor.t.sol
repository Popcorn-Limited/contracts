import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {BaseStrategyTest} from "../../base/BaseStrategyTest.sol";
import {AcrossTestConfigStorage} from "./AcrossTestConfigStorage.sol";
import {AcrossDepositor} from "../../../src/adapter/across/AcrossDepositor.sol";
import {IBaseAdapter, AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";
import {ITestConfigStorage, TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";

contract AcrossDepositorTest is BaseStrategyTest {
    function setUp() public {
        _setUpBaseTest(0);
    }

    function _deployTestConfigStorage() internal override {
        testConfigStorage = ITestConfigStorage(address(new AcrossTestConfigStorage()));
    }

    function _setUpStrategy(
        AdapterConfig memory adapterConfig,
        address owner_
    ) internal override returns (IBaseAdapter) {
        address _strategy = Clones.clone(address(new AcrossDepositor()));

        vm.startPrank(owner_);
        IBaseAdapter(_strategy).initialize(adapterConfig);
        vm.stopPrank();

        return IBaseAdapter(_strategy);
    }

}
