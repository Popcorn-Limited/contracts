// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.0
pragma solidity ^0.8.25;

import {AnyCompounder, AnyCompounderNaive, AnyConverter, ClaimInteraction, IERC20} from "src/strategies/AnyCompounder.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";
import {MockOracle} from "test/utils/mocks/MockOracle.sol";
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

contract AnyCompounderNaiveTest is AnyBaseTest {
    using stdJson for string;

    event ClaimIdProposed(bytes32 id);
    event ClaimIdAdded(bytes32 id);
    event ClaimIdRemoved(bytes32 id);

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
        AnyCompounder _strategy = new AnyCompounder();
        oracle = new MockOracle();

        yieldAsset = json_.readAddress(
            string.concat(".configs[", index_, "].specific.yieldAsset")
        );

        _strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(yieldAsset, address(oracle), uint256(10), uint256(0))
        );

        _strategy.setRewardTokens(
            json.readAddressArray(
                string.concat(".configs[", index_, "].specific.rewardTokens")
            )
        );

        return IBaseStrategy(address(_strategy));
    }

    function _addClaimId(bytes32 claimId) internal {
        AnyCompounder(address(strategy)).proposeClaimId(claimId);

        vm.warp(block.timestamp + 3 days + 1);

        AnyCompounder(address(strategy)).addClaimId(claimId);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM ID TESTS
    //////////////////////////////////////////////////////////////*/

    function test__proposeClaimId() public {
        bytes32 id = keccak256("blub");
        uint256 unlockTime = block.timestamp + 3 days;

        vm.expectEmit(true, true, false, true);
        emit ClaimIdProposed(id);
        AnyCompounder(address(strategy)).proposeClaimId(id);

        assertEq(
            AnyCompounder(address(strategy)).proposedClaimIds(id),
            unlockTime
        );
    }

    function test__proposeClaimId_fails_if_none_owner() public {
        bytes32 id = keccak256("blub");

        vm.startPrank(alice);
        vm.expectRevert("Only the contract owner may perform this action");

        AnyCompounder(address(strategy)).proposeClaimId(id);
    }

    function test__proposeClaimId_fails_if_proposal_exists() public {
        bytes32 id = keccak256("blub");
        AnyCompounder(address(strategy)).proposeClaimId(id);

        vm.expectRevert(AnyConverter.Misconfigured.selector);
        AnyCompounder(address(strategy)).proposeClaimId(id);
    }

    function test__addClaimId() public {
        bytes32 id = keccak256("blub");

        AnyCompounder(address(strategy)).proposeClaimId(id);
        vm.warp(block.timestamp + 3 days + 1);

        vm.expectEmit(true, true, false, true);
        emit ClaimIdAdded(id);
        AnyCompounder(address(strategy)).addClaimId(id);

        assertEq(AnyCompounder(address(strategy)).proposedClaimIds(id), 0);
        assertTrue(AnyCompounder(address(strategy)).claimIds(id));
    }

    function test__addClaimId_fails_if_none_owner() public {
        bytes32 id = keccak256("blub");

        vm.startPrank(alice);
        vm.expectRevert("Only the contract owner may perform this action");

        AnyCompounder(address(strategy)).addClaimId(id);
    }

    function test__addClaimId_respect_timeout() public {
        bytes32 id = keccak256("blub");
        AnyCompounder(address(strategy)).proposeClaimId(id);

        vm.expectRevert(AnyConverter.Misconfigured.selector);
        AnyCompounder(address(strategy)).addClaimId(id);
    }

    function test__addClaimId_fails_if_doesnt_exist() public {
        bytes32 id = keccak256("blub");

        vm.expectRevert(AnyConverter.Misconfigured.selector);
        AnyCompounder(address(strategy)).addClaimId(id);
    }

    function test__removeClaimId() public {
        bytes32 id = keccak256("blub");
        _addClaimId(id);

        vm.expectEmit(true, true, false, true);
        emit ClaimIdRemoved(id);
        AnyCompounder(address(strategy)).removeClaimId(id);

        assertFalse(AnyCompounder(address(strategy)).claimIds(id));
    }

    function test__removeClaimId_fails_if_none_owner() public {
        bytes32 id = keccak256("blub");

        vm.startPrank(alice);
        vm.expectRevert("Only the contract owner may perform this action");

        AnyCompounder(address(strategy)).removeClaimId(id);
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

        // we give the strategy reward tokens to simulate a harvest
        address[] memory rewardTokens = strategy.rewardTokens();
        for (uint256 i; i < rewardTokens.length; i++) {
            deal(rewardTokens[i], address(strategy), 1e18);
        }

        // give this contract yield assets and allow the strategy to pull them
        _mintYieldAsset(testConfig.defaultAmount, address(this));

        ClaimContract claimContract = new ClaimContract(rewardTokens);
        _addClaimId(
            keccak256(
                abi.encodePacked(claimContract, ClaimContract.claim.selector)
            )
        );
        strategy.harvest(
            abi.encode(
                testConfig.defaultAmount,
                ClaimInteraction({
                    addr: address(claimContract),
                    callData: abi.encodeWithSelector(
                        ClaimContract.claim.selector
                    )
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

        // we give the strategy reward tokens to simulate a harvest
        address[] memory rewardTokens = strategy.rewardTokens();
        for (uint256 i; i < rewardTokens.length; i++) {
            deal(rewardTokens[i], address(strategy), 1e18);
        }

        // give this contract yield assets and allow the strategy to pull them
        _mintYieldAsset(testConfig.defaultAmount, address(this));

        ClaimContract claimContract = new ClaimContract(rewardTokens);
        _addClaimId(
            keccak256(
                abi.encodePacked(claimContract, ClaimContract.claim.selector)
            )
        );

        vm.expectRevert(AnyCompounderNaive.HarvestFailed.selector);
        strategy.harvest(
            abi.encode(
                0,
                ClaimInteraction({
                    addr: address(claimContract),
                    callData: abi.encodeWithSelector(
                        ClaimContract.claim.selector
                    )
                })
            )
        );
    }

    function test__harvest_fails_if_not_claimId() public {
        address[] memory rewardTokens = strategy.rewardTokens();
        ClaimContract claimContract = new ClaimContract(rewardTokens);

        vm.expectRevert(AnyConverter.Misconfigured.selector);
        strategy.harvest(
            abi.encode(
                0,
                ClaimInteraction({
                    addr: address(claimContract),
                    callData: abi.encodeWithSelector(
                        ClaimContract.claim.selector
                    )
                })
            )
        );
    }
}
