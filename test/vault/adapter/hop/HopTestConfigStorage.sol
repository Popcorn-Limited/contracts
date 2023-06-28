pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct HopTestConfig {
    address liquidityPool;
    address stakingRewards;
}

contract HopTestConfigStorage is ITestConfigStorage {
    HopTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            //HopTestConfig(0xaa30D6bba6285d0585722e2440Ff89E23EF68864, 0xfD49C7EE330fE060ca66feE33d49206eB96F146D)
            HopTestConfig(
                0xaa30D6bba6285d0585722e2440Ff89E23EF68864,
                0xf587B9309c603feEdf0445aF4D3B21300989e93a
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return
            abi.encode(
                testConfigs[i].liquidityPool,
                testConfigs[i].stakingRewards
            );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
