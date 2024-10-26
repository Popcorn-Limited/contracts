// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.0
pragma solidity ^0.8.25;

import {AnyConverterV2, CallStruct, ProposedChange, PendingTarget} from "src/strategies/any/v2/AnyConverterV2.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, IERC20, Math} from "test/strategies/BaseStrategyTest.sol";
import {MockOracle} from "test/mocks/MockOracle.sol";
import {MockExchange} from "test/mocks/MockExchange.sol";
import "forge-std/console.sol";

abstract contract AnyBaseTest is BaseStrategyTest {
    using Math for uint256;
    using stdJson for string;

    address yieldToken;
    MockOracle oracle;
    MockExchange exchange;

    PendingTarget[] initialTargets;
    CallStruct[] initialAllowances;

    function _setUpBase() internal {
        exchange = new MockExchange();

        PendingTarget[] memory changes = new PendingTarget[](3);
        changes[0] = PendingTarget({
            target: testConfig.asset,
            selector: bytes4(keccak256("approve(address,uint256)")),
            allowed: true
        });
        changes[1] = PendingTarget({
            target: yieldToken,
            selector: bytes4(keccak256("approve(address,uint256)")),
            allowed: true
        });
        changes[2] = PendingTarget({
            target: address(exchange),
            selector: bytes4(
                keccak256(
                    "swapTokenExactAmountIn(address,uint256,address,uint256)"
                )
            ),
            allowed: true
        });

        AnyConverterV2(address(strategy)).proposeTargets(changes);

        vm.warp(block.timestamp + 3 days + 1);
        AnyConverterV2(address(strategy)).updateTargets();
    }

    function _increasePricePerShare(uint256 amount) internal override {
        deal(
            testConfig.asset,
            yieldToken,
            IERC20(testConfig.asset).balanceOf(yieldToken) + amount
        );
    }

    function _mintYieldToken(
        uint256 amount,
        address receiver
    ) internal virtual {
        vm.prank(json.readAddress(string.concat(".configs[0].specific.whale")));
        IERC20(yieldToken).transfer(receiver, amount);
    }

    function _pushFunds(uint256 amountIn, uint256 amountOut) internal {
        _mintYieldToken(amountOut * 2, address(exchange));

        bytes memory encodedApprove = abi.encodeWithSelector(
            bytes4(keccak256("approve(address,uint256)")),
            address(exchange),
            amountIn
        );
        bytes memory encodedSwap = abi.encodeWithSelector(
            bytes4(
                keccak256(
                    "swapTokenExactAmountIn(address,uint256,address,uint256)"
                )
            ),
            testConfig.asset,
            amountIn,
            yieldToken,
            amountOut
        );

        CallStruct[] memory calls = new CallStruct[](2);
        calls[0] = CallStruct(testConfig.asset, encodedApprove);
        calls[1] = CallStruct(address(exchange), encodedSwap);

        strategy.pushFunds(0, abi.encode(calls));

        _mintAsset(amountIn, address(this));
        IERC20(testConfig.asset).approve(address(exchange), amountIn);

        exchange.swapTokenExactAmountIn(
            testConfig.asset,
            amountIn,
            yieldToken,
            amountOut
        );
    }

    function _pullFunds(uint256 amountIn, uint256 amountOut) internal {
        _mintAsset(amountOut * 2, address(exchange));

        bytes memory encodedApprove = abi.encodeWithSelector(
            bytes4(keccak256("approve(address,uint256)")),
            address(exchange),
            amountIn
        );
        bytes memory encodedSwap = abi.encodeWithSelector(
            bytes4(
                keccak256(
                    "swapTokenExactAmountIn(address,uint256,address,uint256)"
                )
            ),
            yieldToken,
            amountIn,
            testConfig.asset,
            amountOut
        );

        CallStruct[] memory calls = new CallStruct[](2);
        calls[0] = CallStruct(yieldToken, encodedApprove);
        calls[1] = CallStruct(address(exchange), encodedSwap);

        strategy.pullFunds(0, abi.encode(calls));
    }

    /*//////////////////////////////////////////////////////////////
                            AUTODEPOSIT
    //////////////////////////////////////////////////////////////*/

    /// @dev Partially withdraw assets directly from strategy and the underlying protocol
    function test__withdraw_autoDeposit_partial() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        // Push 40% the funds into the underlying protocol
        uint256 pushAmount = (testConfig.defaultAmount / 5) * 2;
        _pushFunds(pushAmount, pushAmount);

        // Withdraw 20% of deposit
        vm.prank(bob);
        strategy.withdraw(testConfig.defaultAmount / 5, bob, bob);

        assertApproxEqAbs(
            strategy.totalAssets(),
            (testConfig.defaultAmount / 5) * 4,
            _delta_,
            "ta"
        );
        assertApproxEqAbs(
            strategy.totalSupply(),
            (testConfig.defaultAmount / 5) * 4,
            _delta_,
            "ts"
        );
        assertApproxEqAbs(
            strategy.balanceOf(bob),
            (testConfig.defaultAmount / 5) * 4,
            _delta_,
            "share bal"
        );
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(bob),
            testConfig.defaultAmount / 5,
            _delta_,
            "asset bal"
        );
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(address(strategy)),
            (testConfig.defaultAmount / 5) * 2,
            _delta_,
            "strategy asset bal"
        );
    }

    /// @dev Partially redeem assets directly from strategy and the underlying protocol
    function test__redeem_autoDeposit_partial() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        // Push 40% the funds into the underlying protocol
        uint256 pushAmount = (testConfig.defaultAmount / 5) * 2;
        _pushFunds(pushAmount, pushAmount);

        // Redeem 20% of deposit
        vm.prank(bob);
        strategy.redeem(testConfig.defaultAmount / 5, bob, bob);

        assertApproxEqAbs(
            strategy.totalAssets(),
            (testConfig.defaultAmount / 5) * 4,
            _delta_,
            "ta"
        );
        assertApproxEqAbs(
            strategy.totalSupply(),
            (testConfig.defaultAmount / 5) * 4,
            _delta_,
            "ts"
        );
        assertApproxEqAbs(
            strategy.balanceOf(bob),
            (testConfig.defaultAmount / 5) * 4,
            _delta_,
            "share bal"
        );
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(bob),
            testConfig.defaultAmount / 5,
            _delta_,
            "asset bal"
        );
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(address(strategy)),
            (testConfig.defaultAmount / 5) * 2,
            _delta_,
            "strategy asset bal"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            PUSH/PULL FUNDS
    //////////////////////////////////////////////////////////////*/

    function test__pushFunds() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        uint256 oldTa = strategy.totalAssets();
        uint256 oldTs = strategy.totalSupply();

        _pushFunds(testConfig.defaultAmount, testConfig.defaultAmount);

        assertEq(
            IERC20(yieldToken).balanceOf(address(strategy)),
            testConfig.defaultAmount
        );
        assertEq(IERC20(testConfig.asset).balanceOf(address(strategy)), 0);

        assertApproxEqAbs(strategy.totalAssets(), oldTa, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
    }

    function test__pushFunds_with_slippage() public {
        strategy.toggleAutoDeposit();
        // Change slippage
        AnyConverterV2(address(strategy)).proposeSlippage(1000);
        vm.warp(block.timestamp + 3 days + 1);
        AnyConverterV2(address(strategy)).changeSlippage();

        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        uint256 oldTa = strategy.totalAssets();
        uint256 oldTs = strategy.totalSupply();

        uint256 amountIn = testConfig.defaultAmount / 2;
        uint256 expectedAmountOut = amountIn.mulDiv(
            9000,
            10_000,
            Math.Rounding.Floor
        );
        _pushFunds(amountIn, expectedAmountOut);

        assertEq(
            IERC20(yieldToken).balanceOf(address(strategy)),
            expectedAmountOut
        );
        assertEq(
            IERC20(testConfig.asset).balanceOf(address(strategy)),
            testConfig.defaultAmount - amountIn
        );

        assertApproxEqAbs(
            strategy.totalAssets(),
            testConfig.defaultAmount / 2 + expectedAmountOut,
            _delta_,
            "ta"
        );
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
    }

    function test__pullFunds() public override {
        test__pushFunds();

        uint256 oldTa = strategy.totalAssets();
        uint256 oldTs = strategy.totalSupply();

        _pullFunds(testConfig.defaultAmount, testConfig.defaultAmount);

        assertEq(IERC20(yieldToken).balanceOf(address(strategy)), 0);
        assertEq(
            IERC20(testConfig.asset).balanceOf(address(strategy)),
            testConfig.defaultAmount
        );

        assertApproxEqAbs(strategy.totalAssets(), oldTa, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
    }

    function test__pullFunds_with_slippage() public {
        test__pushFunds();

        uint256 oldTa = strategy.totalAssets();
        uint256 oldTs = strategy.totalSupply();

        // Add slippage
        AnyConverterV2(address(strategy)).proposeSlippage(1000);
        vm.warp(block.timestamp + 3 days + 1);
        AnyConverterV2(address(strategy)).changeSlippage();

        uint256 amountIn = testConfig.defaultAmount / 2;
        uint256 expectedAmountOut = amountIn.mulDiv(
            9000,
            10_000,
            Math.Rounding.Floor
        );
        _pullFunds(amountIn, expectedAmountOut);

        // warp adds some assets as interest from the aToken
        assertEq(
            IERC20(yieldToken).balanceOf(address(strategy)),
            500567815567176224
        );
        assertEq(
            IERC20(testConfig.asset).balanceOf(address(strategy)),
            expectedAmountOut
        );

        // TODO reduce by slippage
        assertApproxEqAbs(
            strategy.totalAssets(),
            500567815567176224 + expectedAmountOut,
            _delta_,
            "ta"
        );
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
    }

    function testFail__pushFunds_invalid_call() public {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        CallStruct[] memory calls = new CallStruct[](2);
        calls[0] = CallStruct(
            yieldToken,
            abi.encodeWithSelector(
                bytes4(keccak256("transfer(address,uint256)")),
                address(exchange),
                testConfig.defaultAmount
            )
        );

        vm.expectRevert("Not Allowed");
        strategy.pushFunds(0, abi.encode(calls));
    }

    function testFail__pullFunds_invalid_call() public {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);
        _pushFunds(testConfig.defaultAmount, testConfig.defaultAmount);

        CallStruct[] memory calls = new CallStruct[](2);
        calls[0] = CallStruct(
            yieldToken,
            abi.encodeWithSelector(
                bytes4(keccak256("transfer(address,uint256)")),
                address(exchange),
                testConfig.defaultAmount
            )
        );

        vm.expectRevert("Not Allowed");
        strategy.pullFunds(0, abi.encode(calls));
    }

    /*//////////////////////////////////////////////////////////////
                            SET SLIPPAGE
    //////////////////////////////////////////////////////////////*/

    function test__proposeSlippage() public {
        uint256 newSlippage = 500; // 5%
        AnyConverterV2(address(strategy)).proposeSlippage(newSlippage);

        (uint256 proposedSlippage, uint256 proposedTime) = AnyConverterV2(
            address(strategy)
        ).proposedSlippage();
        assertEq(
            proposedSlippage,
            newSlippage,
            "Proposed slippage should match"
        );
        assertEq(
            proposedTime,
            block.timestamp + 3 days,
            "Proposed time should be current block timestamp"
        );
    }

    function test__proposeSlippage_owner_only() public {
        uint256 newSlippage = 500; // 5%

        vm.prank(bob);
        vm.expectRevert("Only the contract owner may perform this action");
        AnyConverterV2(address(strategy)).proposeSlippage(newSlippage);
    }

    function test__proposeSlippage_invalid_value() public {
        uint256 invalidSlippage = 10001; // 100.01%, which is invalid

        vm.expectRevert(AnyConverterV2.Misconfigured.selector);
        AnyConverterV2(address(strategy)).proposeSlippage(invalidSlippage);
    }

    function test__proposeSlippage_multiple_proposals() public {
        uint256 firstSlippage = 500; // 5%
        uint256 secondSlippage = 1000; // 10%

        AnyConverterV2(address(strategy)).proposeSlippage(firstSlippage);

        (uint256 proposedSlippage, uint256 firstProposedTime) = AnyConverterV2(
            address(strategy)
        ).proposedSlippage();
        assertEq(
            proposedSlippage,
            firstSlippage,
            "First proposed slippage should match"
        );

        // Warp time forward
        vm.warp(block.timestamp + 1 days);

        AnyConverterV2(address(strategy)).proposeSlippage(secondSlippage);

        (
            uint256 secondProposedSlippage,
            uint256 secondProposedTime
        ) = AnyConverterV2(address(strategy)).proposedSlippage();
        assertEq(
            secondProposedSlippage,
            secondSlippage,
            "Second proposed slippage should match"
        );
        assertGt(
            secondProposedTime,
            firstProposedTime,
            "Second proposal time should be later"
        );
    }

    function test__changeSlippage() public {
        uint256 newSlippage = 500; // 5%
        AnyConverterV2(address(strategy)).proposeSlippage(newSlippage);

        // Warp time forward past the required delay
        vm.warp(block.timestamp + 3 days + 1);

        AnyConverterV2(address(strategy)).changeSlippage();

        uint256 currentSlippage = AnyConverterV2(address(strategy)).slippage();
        assertEq(currentSlippage, newSlippage, "Slippage should be updated");
    }

    function test__changeSlippage_owner_only() public {
        uint256 newSlippage = 500; // 5%
        AnyConverterV2(address(strategy)).proposeSlippage(newSlippage);

        vm.warp(block.timestamp + 3 days + 1);

        vm.prank(bob);
        vm.expectRevert("Only the contract owner may perform this action");
        AnyConverterV2(address(strategy)).changeSlippage();
    }

    function test__changeSlippage_before_delay() public {
        uint256 newSlippage = 500; // 5%
        AnyConverterV2(address(strategy)).proposeSlippage(newSlippage);

        vm.expectRevert(AnyConverterV2.Misconfigured.selector);
        AnyConverterV2(address(strategy)).changeSlippage();
    }

    function test__changeSlippage_no_proposal() public {
        vm.expectRevert(AnyConverterV2.Misconfigured.selector);
        AnyConverterV2(address(strategy)).changeSlippage();
    }

    function test__changeSlippage_resets_proposal() public {
        uint256 newSlippage = 500; // 5%
        AnyConverterV2(address(strategy)).proposeSlippage(newSlippage);

        vm.warp(block.timestamp + 3 days + 1);

        AnyConverterV2(address(strategy)).changeSlippage();

        (uint256 proposedSlippage, ) = AnyConverterV2(address(strategy))
            .proposedSlippage();
        assertEq(proposedSlippage, 0, "Proposed slippage should be reset");
    }

    /*//////////////////////////////////////////////////////////////
                            SET TARGETS
    //////////////////////////////////////////////////////////////*/

    function _getProposedTargets()
        internal
        view
        returns (PendingTarget[] memory)
    {
        address target = address(0x444);
        bytes4 selector = bytes4(keccak256("someFunction(uint256)"));
        PendingTarget[] memory changes = new PendingTarget[](1);
        changes[0] = PendingTarget({
            target: target,
            selector: selector,
            allowed: true
        });
        return changes;
    }

    function test__proposeTargets() public {
        PendingTarget[] memory changes = _getProposedTargets();
        AnyConverterV2(address(strategy)).proposeTargets(changes);

        (
            uint256 proposedTime,
            PendingTarget[] memory proposed
        ) = AnyConverterV2(address(strategy)).getProposedTargets();

        assertEq(proposed.length, 1);
        assertEq(proposed[0].selector, changes[0].selector);
        assertEq(proposed[0].target, changes[0].target);
        assertEq(proposed[0].allowed, true);
        assertEq(proposedTime, block.timestamp + 3 days);
    }

    function test__proposeTargets_owner_only() public {
        PendingTarget[] memory changes = _getProposedTargets();

        vm.prank(bob);
        vm.expectRevert("Only the contract owner may perform this action");
        AnyConverterV2(address(strategy)).proposeTargets(changes);
    }

    function test__proposeTargets_multiple_proposal() public {
        uint256 firstCallTime = block.timestamp;
        PendingTarget[] memory changes = _getProposedTargets();
        AnyConverterV2(address(strategy)).proposeTargets(changes);

        // Warp time forward
        vm.warp(block.timestamp + 1 days);

        changes[0] = PendingTarget({
            target: address(0x333),
            selector: bytes4(keccak256("someOtherFunction(uint256)")),
            allowed: true
        });

        AnyConverterV2(address(strategy)).proposeTargets(changes);
        (
            uint256 proposedTime,
            PendingTarget[] memory proposed
        ) = AnyConverterV2(address(strategy)).getProposedTargets();

        // Should add both proposals
        assertEq(proposed.length, 2);
        assertEq(proposed[0].target, address(0x444));
        assertEq(
            proposed[0].selector,
            bytes4(keccak256("someFunction(uint256)"))
        );
        assertEq(proposed[0].allowed, true);
        assertEq(proposed[1].target, address(0x333));
        assertEq(
            proposed[1].selector,
            bytes4(keccak256("someOtherFunction(uint256)"))
        );
        assertEq(proposed[1].allowed, true);
        assertEq(proposedTime, firstCallTime + 4 days);
    }

    function test__updateTargets() public {
        PendingTarget[] memory changes = _getProposedTargets();
        AnyConverterV2(address(strategy)).proposeTargets(changes);

        // Warp time forward past the required delay
        vm.warp(block.timestamp + 3 days + 1);

        // Change allowances
        AnyConverterV2(address(strategy)).updateTargets();

        (
            uint256 proposedTime,
            PendingTarget[] memory proposed
        ) = AnyConverterV2(address(strategy)).getProposedTargets();

        assertEq(proposedTime, 0);
        assertEq(proposed.length, 0);

        assertTrue(
            AnyConverterV2(address(strategy)).isAllowed(
                address(0x444),
                bytes4(keccak256("someFunction(uint256)"))
            )
        );
    }

    function test__updateTargets_owner_only() public {
        PendingTarget[] memory changes = _getProposedTargets();
        AnyConverterV2(address(strategy)).proposeTargets(changes);

        // Warp time forward past the required delay
        vm.warp(block.timestamp + 3 days + 1);

        vm.prank(bob);
        vm.expectRevert("Only the contract owner may perform this action");
        AnyConverterV2(address(strategy)).updateTargets();
    }

    function test__updateTargets_before_delay() public {
        PendingTarget[] memory changes = _getProposedTargets();
        AnyConverterV2(address(strategy)).proposeTargets(changes);

        vm.expectRevert(AnyConverterV2.Misconfigured.selector);
        AnyConverterV2(address(strategy)).updateTargets();
    }

    function test__updateTargets_no_proposal() public {
        vm.expectRevert(AnyConverterV2.Misconfigured.selector);
        AnyConverterV2(address(strategy)).updateTargets();
    }

    /*//////////////////////////////////////////////////////////////
                            SET ALLOWANCE
    //////////////////////////////////////////////////////////////*/

    function _getProposedAllowances()
        internal
        view
        returns (CallStruct[] memory)
    {
        CallStruct[] memory changes = new CallStruct[](1);
        changes[0] = CallStruct({
            target: testConfig.asset,
            data: abi.encodeWithSelector(
                bytes4(keccak256("approve(address,uint256)")),
                address(exchange),
                type(uint256).max
            )
        });
        return changes;
    }

    function test__proposeAllowances() public {
        CallStruct[] memory changes = _getProposedAllowances();
        AnyConverterV2(address(strategy)).proposeAllowances(changes);

        (uint256 proposedTime, CallStruct[] memory proposed) = AnyConverterV2(
            address(strategy)
        ).getProposedAllowances();

        assertEq(proposed.length, 1, "length");
        assertEq(proposed[0].target, changes[0].target, "target");
        assertEq(proposed[0].data, changes[0].data, "data");
        assertEq(proposedTime, block.timestamp + 3 days, "time");
    }

    function test__proposeAllowances_owner_only() public {
        CallStruct[] memory changes = _getProposedAllowances();

        vm.prank(bob);
        vm.expectRevert("Only the contract owner may perform this action");
        AnyConverterV2(address(strategy)).proposeAllowances(changes);
    }

    function test__proposeAllowances_multiple_proposal() public {
        uint256 firstCallTime = block.timestamp;
        CallStruct[] memory changes = _getProposedAllowances();
        AnyConverterV2(address(strategy)).proposeAllowances(changes);

        // Warp time forward
        vm.warp(block.timestamp + 1 days);

        changes[0] = CallStruct({
            target: testConfig.asset,
            data: abi.encodeWithSelector(
                bytes4(keccak256("approve(address,uint256)")),
                address(exchange),
                0
            )
        });

        AnyConverterV2(address(strategy)).proposeAllowances(changes);
        (uint256 proposedTime, CallStruct[] memory proposed) = AnyConverterV2(
            address(strategy)
        ).getProposedAllowances();

        // Should add both proposals
        assertEq(proposed.length, 2);
        assertEq(proposed[0].target, testConfig.asset);
        assertEq(
            proposed[0].data,
            abi.encodeWithSelector(
                bytes4(keccak256("approve(address,uint256)")),
                address(exchange),
                type(uint256).max
            )
        );
        assertEq(proposed[1].target, testConfig.asset);
        assertEq(
            proposed[1].data,
            abi.encodeWithSelector(
                bytes4(keccak256("approve(address,uint256)")),
                address(exchange),
                0
            )
        );
        assertEq(proposedTime, firstCallTime + 4 days);
    }

    function test__updateAllowances() public {
        CallStruct[] memory changes = _getProposedAllowances();
        AnyConverterV2(address(strategy)).proposeAllowances(changes);

        // Warp time forward past the required delay
        vm.warp(block.timestamp + 3 days + 1);

        // Change allowances
        AnyConverterV2(address(strategy)).updateAllowances();

        (uint256 proposedTime, CallStruct[] memory proposed) = AnyConverterV2(
            address(strategy)
        ).getProposedAllowances();

        assertEq(proposedTime, 0);
        assertEq(proposed.length, 0);

        assertEq(
            IERC20(testConfig.asset).allowance(
                address(strategy),
                address(exchange)
            ),
            type(uint256).max
        );
    }

    function test__updateAllowances_owner_only() public {
        CallStruct[] memory changes = _getProposedAllowances();
        AnyConverterV2(address(strategy)).proposeAllowances(changes);

        // Warp time forward past the required delay
        vm.warp(block.timestamp + 3 days + 1);

        vm.prank(bob);
        vm.expectRevert("Only the contract owner may perform this action");
        AnyConverterV2(address(strategy)).updateAllowances();
    }

    function test__updateAllowances_before_delay() public {
        CallStruct[] memory changes = _getProposedAllowances();
        AnyConverterV2(address(strategy)).proposeAllowances(changes);

        vm.expectRevert(AnyConverterV2.Misconfigured.selector);
        AnyConverterV2(address(strategy)).updateAllowances();
    }

    function test__updateAllowances_no_proposal() public {
        vm.expectRevert(AnyConverterV2.Misconfigured.selector);
        AnyConverterV2(address(strategy)).updateAllowances();
    }

    /*//////////////////////////////////////////////////////////////
                            RESCUE TOKEN
    //////////////////////////////////////////////////////////////*/

    function test__rescueToken() public {
        IERC20 rescueToken = IERC20(
            json.readAddress(string.concat(".configs[0].specific.rescueToken"))
        );
        uint256 rescueAmount = 10e18;
        deal(address(rescueToken), bob, rescueAmount);

        vm.prank(bob);
        rescueToken.transfer(address(strategy), rescueAmount);

        AnyConverterV2(address(strategy)).rescueToken(address(rescueToken));

        assertEq(rescueToken.balanceOf(address(strategy)), 0);
        assertEq(rescueToken.balanceOf(address(this)), rescueAmount);
    }

    function testFail__rescueToken_non_owner() public {
        IERC20 rescueToken = IERC20(
            json.readAddress(string.concat(".configs[0].specific.rescueToken"))
        );
        uint256 rescueAmount = 10e18;
        deal(address(rescueToken), bob, rescueAmount);

        vm.prank(bob);
        rescueToken.transfer(address(strategy), rescueAmount);

        vm.prank(bob);
        AnyConverterV2(address(strategy)).rescueToken(address(rescueToken));
    }

    function test__rescueToken_token_is_in_tokens_error() public {
        vm.expectRevert(AnyConverterV2.Misconfigured.selector);
        AnyConverterV2(address(strategy)).rescueToken(testConfig.asset);
    }
}
