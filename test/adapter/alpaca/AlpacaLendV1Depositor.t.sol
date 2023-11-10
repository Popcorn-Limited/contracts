import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {BaseStrategyTest} from "../../base/BaseStrategyTest.sol";
import {AlpacaTestConfigStorage} from "./AlpacaTestConfigStorage.sol";
import {IBaseAdapter, AdapterConfig} from "../../../src/base/interfaces/IBaseAdapter.sol";
import {ITestConfigStorage, TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {AlpacaLendV1Depositor} from "../../../src/adapter/alpaca/alpacaLendV1/AlpacaLendV1Depositor.sol";

contract AlpacaLendV1DepositorTest is BaseStrategyTest {
    function setUp() public {
        _setUpBaseTest(0);
    }

    function _deployTestConfigStorage() internal override {
        testConfigStorage = ITestConfigStorage(address(new AlpacaTestConfigStorage()));
    }

    function _setUpStrategy(
        AdapterConfig memory adapterConfig,
        address owner_
    ) internal override returns (IBaseAdapter) {
        address _strategy = Clones.clone(address(new AlpacaLendV1Depositor()));

        vm.startPrank(owner_);
        IBaseAdapter(_strategy).initialize(adapterConfig);
        vm.stopPrank();

        return IBaseAdapter(_strategy);
    }

}
