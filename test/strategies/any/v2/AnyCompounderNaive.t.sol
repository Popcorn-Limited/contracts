// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.0
pragma solidity ^0.8.25;

import {AnyCompounderV2, AnyCompounderNaiveV2, AnyConverterV2, CallStruct, PendingCallAllowance, IERC20} from "src/strategies/any/v2/AnyCompounderV2.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "test/strategies/BaseStrategyTest.sol";
import {MockOracle} from "test/mocks/MockOracle.sol";
import {AnyBaseTest} from "./AnyBase.t.sol";
import "forge-std/console.sol";

contract ClaimContract {
    address[] public rewardTokens;

    constructor(address[] memory _rewardTokens) {
        rewardTokens = _rewardTokens;
    }

    function claim() external {
        for (uint256 i; i < rewardTokens.length; i++) {
            IERC20(rewardTokens[i]).transfer(
                msg.sender,
                IERC20(rewardTokens[i]).balanceOf(address(this))
            );
        }
    }
}

contract AnyCompounderNaiveV2Test is AnyBaseTest {
    using stdJson for string;

    event ClaimIdProposed(bytes32 id);
    event ClaimIdAdded(bytes32 id);
    event ClaimIdRemoved(bytes32 id);

    ClaimContract public claimContract;

    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/any/v2/AnyCompounderNaiveTestConfig.json"
        );
        _setUpBase();
    }

    function _setUpStrategy(
        string memory json_,
        string memory index_,
        TestConfig memory testConfig_
    ) internal override returns (IBaseStrategy) {
        AnyCompounderV2 _strategy = new AnyCompounderV2();
        oracle = new MockOracle();

        yieldToken = json_.readAddress(
            string.concat(".configs[", index_, "].specific.yieldToken")
        );

        _strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(yieldToken, address(oracle), uint256(0), uint256(0))
        );

        _strategy.setRewardTokens(
            json.readAddressArray(
                string.concat(".configs[", index_, "].specific.rewardTokens")
            )
        );

        return IBaseStrategy(address(_strategy));
    }

    function _prepareClaim() internal {
        address[] memory rewardTokens = strategy.rewardTokens();
        claimContract = new ClaimContract(rewardTokens);

        for (uint256 i; i < rewardTokens.length; i++) {
            deal(rewardTokens[i], address(claimContract), 1e18);
        }

        // Give this contract yield assets and allow the strategy to pull them
        _mintYieldToken(testConfig.defaultAmount, address(this));
        IERC20(yieldToken).approve(address(strategy), testConfig.defaultAmount);

        // Approve claim call
        address target = address(claimContract);
        bytes4 selector = bytes4(
            abi.encodeWithSelector(ClaimContract.claim.selector)
        );
        PendingCallAllowance[] memory changes = new PendingCallAllowance[](1);
        changes[0] = PendingCallAllowance({
            target: target,
            selector: selector,
            allowed: true
        });
        AnyConverterV2(address(strategy)).proposeCallAllowance(changes);
        vm.warp(block.timestamp + 3 days + 1);
        AnyConverterV2(address(strategy)).changeCallAllowances();
    }

    /*//////////////////////////////////////////////////////////////
                            HARVEST TESTS
    //////////////////////////////////////////////////////////////*/

    function test_harvest_should_increase_total_assets() public {
        // base code to have != total assets
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        uint256 totalAssets = strategy.totalAssets();
        uint256 totalSupply = strategy.totalSupply();

        _prepareClaim();
        strategy.harvest(
            abi.encode(
                testConfig.defaultAmount,
                CallStruct({
                    target: address(claimContract),
                    data: abi.encodeWithSelector(ClaimContract.claim.selector)
                })
            )
        );

        assertGt(
            strategy.totalAssets(),
            totalAssets,
            "total assets should increase"
        );
        assertEq(
            strategy.totalSupply(),
            totalSupply,
            "total supply should not change"
        );
    }

    function test_harvest_should_fail_if_total_assets_does_not_increase()
        public
    {
        // base code to have != total assets
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        _prepareClaim();

        vm.expectRevert(AnyCompounderNaiveV2.HarvestFailed.selector);
        strategy.harvest(
            abi.encode(
                0,
                CallStruct({
                    target: address(claimContract),
                    data: abi.encodeWithSelector(ClaimContract.claim.selector)
                })
            )
        );
    }
}
