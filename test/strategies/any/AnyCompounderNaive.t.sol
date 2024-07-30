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

contract ClaimContract {
    address[] public rewardTokens;
    constructor(address[] memory _rewardTokens) {
        rewardTokens = _rewardTokens;
    }

    fallback() external {
        for (uint i; i < rewardTokens.length; i++) {
            IERC20(rewardTokens[i]).transfer(msg.sender, IERC20(rewardTokens[i]).balanceOf(address(this)));
        }
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

        _strategy.setRewardTokens(json.readAddressArray(string.concat(".configs[", index_, "].specific.rewardTokens")));

        return IBaseStrategy(address(_strategy));
    }

    function test_harvest_should_increase_total_assets() public {
        // base code to have != total assets
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);
    
        uint totalAssets = strategy.totalAssets();
        uint totalSupply = strategy.totalSupply();

        // we give the strategy reward tokens to simulate a harvest
        address[] memory rewardTokens = strategy.rewardTokens();
        for (uint i; i < rewardTokens.length; i++) {
            deal(rewardTokens[i], address(strategy), 1e18);
        }
        
        // give this contract yield assets and allow the strategy to pull them
        _prepareConversion(yieldAsset, testConfig.defaultAmount);

        ClaimContract claimContract = new ClaimContract(rewardTokens);
        strategy.harvest(abi.encode(
            claimContract,
            bytes(""),
            testConfig.defaultAmount
        ));

        assertGt(strategy.totalAssets(), totalAssets, "total assets should increase");
        assertEq(strategy.totalSupply(), totalSupply, "total supply should not change");
    }

    function test_harvest_should_fail_if_total_assets_does_not_increase() public {
        // base code to have != total assets
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);
    
        // we give the strategy reward tokens to simulate a harvest
        address[] memory rewardTokens = strategy.rewardTokens();
        for (uint i; i < rewardTokens.length; i++) {
            deal(rewardTokens[i], address(strategy), 1e18);
        }
        
        // give this contract yield assets and allow the strategy to pull them
        _prepareConversion(yieldAsset, testConfig.defaultAmount);

        ClaimContract claimContract = new ClaimContract(rewardTokens);

        vm.expectRevert(AnyCompounderNaive.HarvestFailed.selector);
        strategy.harvest(abi.encode(
            claimContract,
            bytes(""),
            0
        ));
    }
}

