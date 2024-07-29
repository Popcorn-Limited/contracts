// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.0
pragma solidity ^0.8.25;

import {AnyCompounderNaive, IERC20} from "src/strategies/AnyCompounderNaive.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";
import {MockOracle} from "test/utils/mocks/MockOracle.sol";
import {AnyBaseTest} from "./AnyBase.t.sol";
import "forge-std/console.sol";

contract AnyCompounderNaiveImpl is AnyCompounderNaive {
    function initialize(
        address asset_,
        address owner_,
        bool autoDeposit_,
        bytes memory strategyInitData_
    ) external initializer {
        __AnyConverter_init(asset_, owner_, autoDeposit_, strategyInitData_);
    }
}


contract AnyCompounderNaiveTest is AnyBaseTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/any/AnyCompounderNaiveTestConfig.json"
        );
    }
    
    function _setUpStrategy(
        string memory json_,
        string memory index_,
        TestConfig memory testConfig_
    ) internal override returns (IBaseStrategy) {
        AnyCompounderNaiveImpl _strategy = new AnyCompounderNaiveImpl();
        MockOracle oracle = new MockOracle();

        yieldAsset = json_.readAddress(
            string.concat(".configs[", index_, "].specific.yieldAsset")
        );

        _strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(yieldAsset, address(oracle), uint256(10), uint256(0))
        );

        return IBaseStrategy(address(_strategy));
    }

}