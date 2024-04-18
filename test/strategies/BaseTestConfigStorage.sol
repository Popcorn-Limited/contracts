import {TestConfig, ITestConfigStorage} from "./ITestConfigStorage.sol";

abstract contract BaseTestConfigStorage is ITestConfigStorage {
    TestConfig[] internal _testConfigs;
    AdapterConfig[] internal _adapterConfigs;

    function getTestConfigLength() public view returns (uint256) {
        return _testConfigs.length;
    }

    function getAdapterConfigLength() public view returns (uint) {
        return _adapterConfigs.length;
    }

    function getTestConfig(
        uint256 i
    ) public view returns (TestConfig memory) {
        if (i >= _testConfigs.length) revert("NO_CONFIG");
        return _testConfigs[i];
    }

    function getAdapterConfig(
        uint256 i
    ) public view returns (AdapterConfig memory) {
        if (i >= _adapterConfigs.length) revert("NO_CONFIG");
        return _adapterConfigs[i];
    }
}