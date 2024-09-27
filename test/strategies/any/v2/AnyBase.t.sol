// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.0
pragma solidity ^0.8.25;

import {AnyConverterV2, CallStruct, ProposedChange, PendingAllowance} from "src/strategies/AnyConverterV2.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, IERC20, Math} from "../../BaseStrategyTest.sol";
import {MockOracle} from "test/mocks/MockOracle.sol";
import {MockExchange} from "test/mocks/MockExchange.sol";
import "forge-std/console.sol";

abstract contract AnyV2BaseTest is BaseStrategyTest {
    using Math for uint256;
    using stdJson for string;

    address yieldToken;
    MockOracle oracle;
    MockExchange exchange;

    function _setUpBase() internal {
        exchange = new MockExchange();
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
        _mintYieldToken(amountOut, address(exchange));

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

        strategy.pushFunds(0, abi.encode(bytes(""), calls));
    }

    function _pullFunds(uint256 amountIn, uint256 amountOut) internal {
        _mintAsset(amountOut, address(exchange));

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

        strategy.pushFunds(0, abi.encode(bytes(""), calls));
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
            (testConfig.defaultAmount / 5) * 4,
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
            (testConfig.defaultAmount / 5) * 4,
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

        // TODO reduce by slippage
        assertApproxEqAbs(strategy.totalAssets(), oldTa, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
    }

    function test__pullFunds() public override {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        _pushFunds(testConfig.defaultAmount, testConfig.defaultAmount);

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
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        _pushFunds(testConfig.defaultAmount, testConfig.defaultAmount);

        // Add slippage
        AnyConverterV2(address(strategy)).proposeSlippage(1000);
        vm.warp(block.timestamp + 3 days + 1);
        AnyConverterV2(address(strategy)).changeSlippage();

        uint256 oldTa = strategy.totalAssets();
        uint256 oldTs = strategy.totalSupply();

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
            445012582609314989
        );
        assertEq(
            IERC20(testConfig.asset).balanceOf(address(strategy)),
            assetAmount
        );

        // TODO reduce by slippage
        assertApproxEqAbs(strategy.totalAssets(), oldTa, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
    }

    function testFail__pushFunds_invalid_call() public {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        // TODO actual reverting call
    }

    function testFail__pullFunds_invalid_call() public {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);
        _pushFunds(testConfig.defaultAmount, testConfig.defaultAmount);

        // TODO actual reverting call
    }

    /*//////////////////////////////////////////////////////////////
                            SET SLIPPAGE
    //////////////////////////////////////////////////////////////*/

    function test__proposeSlippage() public {
        uint256 newSlippage = 500; // 5%
        AnyConverterV2(address(strategy)).proposeSlippage(newSlippage);

        (uint256 proposedSlippage, uint256 proposedTime) = AnyConverterV2(address(strategy)).proposedSlippage();
        assertEq(proposedSlippage, newSlippage, "Proposed slippage should match");
        assertEq(proposedTime, block.timestamp, "Proposed time should be current block timestamp");
    }

    function test__proposeSlippage_owner_only() public {
        uint256 newSlippage = 500; // 5%
        
        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        AnyConverterV2(address(strategy)).proposeSlippage(newSlippage);
    }

    function test__proposeSlippage_invalid_value() public {
        uint256 invalidSlippage = 10001; // 100.01%, which is invalid
        
        vm.expectRevert(AnyConverterV2.InvalidConfig.selector);
        AnyConverterV2(address(strategy)).proposeSlippage(invalidSlippage);
    }

    function test__proposeSlippage_multiple_proposals() public {
        uint256 firstSlippage = 500; // 5%
        uint256 secondSlippage = 1000; // 10%

        AnyConverterV2(address(strategy)).proposeSlippage(firstSlippage);
        
        (uint256 proposedSlippage, uint256 firstProposedTime) = AnyConverterV2(address(strategy)).proposedSlippage();
        assertEq(proposedSlippage, firstSlippage, "First proposed slippage should match");

        // Warp time forward
        vm.warp(block.timestamp + 1 days);

        AnyConverterV2(address(strategy)).proposeSlippage(secondSlippage);
        
        (proposedSlippage, uint256 secondProposedTime) = AnyConverterV2(address(strategy)).proposedSlippage();
        assertEq(proposedSlippage, secondSlippage, "Second proposed slippage should match");
        assertGt(secondProposedTime, firstProposedTime, "Second proposal time should be later");
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
        vm.expectRevert("Ownable: caller is not the owner");
        AnyConverterV2(address(strategy)).changeSlippage();
    }

    function test__changeSlippage_before_delay() public {
        uint256 newSlippage = 500; // 5%
        AnyConverterV2(address(strategy)).proposeSlippage(newSlippage);

        // Warp time forward, but not past the required delay
        vm.warp(block.timestamp + 3 days);

        vm.expectRevert(AnyConverterV2.TimelockNotReady.selector);
        AnyConverterV2(address(strategy)).changeSlippage();
    }

    function test__changeSlippage_no_proposal() public {
        vm.expectRevert(AnyConverterV2.NoProposal.selector);
        AnyConverterV2(address(strategy)).changeSlippage();
    }

    function test__changeSlippage_resets_proposal() public {
        uint256 newSlippage = 500; // 5%
        AnyConverterV2(address(strategy)).proposeSlippage(newSlippage);

        vm.warp(block.timestamp + 3 days + 1);

        AnyConverterV2(address(strategy)).changeSlippage();

        (uint256 proposedSlippage, ) = AnyConverterV2(address(strategy)).proposedSlippage();
        assertEq(proposedSlippage, 0, "Proposed slippage should be reset");
    }

    /*//////////////////////////////////////////////////////////////
                            SET ALLOWED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test__proposeAllowed() public {
        bytes4 newAllowedFunction = bytes4(keccak256("someFunction(uint256)"));
        AnyConverterV2(address(strategy)).proposeAllowed(newAllowedFunction);

        (bytes4 proposedAllowed, uint256 proposedTime) = AnyConverterV2(address(strategy)).proposedAllowed();
        assertEq(proposedAllowed, newAllowedFunction, "Proposed allowed function should match");
        assertEq(proposedTime, block.timestamp, "Proposed time should be current block timestamp");
    }

    function test__proposeAllowed_owner_only() public {
        bytes4 newAllowedFunction = bytes4(keccak256("someFunction(uint256)"));
        
        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        AnyConverterV2(address(strategy)).proposeAllowed(newAllowedFunction);
    }

    function test__proposeAllowed_zero_selector() public {
        bytes4 zeroSelector = bytes4(0);
        
        vm.expectRevert(AnyConverterV2.InvalidConfig.selector);
        AnyConverterV2(address(strategy)).proposeAllowed(zeroSelector);
    }

    function test__proposeAllowed_multiple_proposals() public {
        bytes4 firstAllowed = bytes4(keccak256("firstFunction(uint256)"));
        bytes4 secondAllowed = bytes4(keccak256("secondFunction(address)"));

        AnyConverterV2(address(strategy)).proposeAllowed(firstAllowed);
        
        (bytes4 proposedAllowed, uint256 firstProposedTime) = AnyConverterV2(address(strategy)).proposedAllowed();
        assertEq(proposedAllowed, firstAllowed, "First proposed allowed should match");

        // Warp time forward
        vm.warp(block.timestamp + 1 days);

        AnyConverterV2(address(strategy)).proposeAllowed(secondAllowed);
        
        (proposedAllowed, uint256 secondProposedTime) = AnyConverterV2(address(strategy)).proposedAllowed();
        assertEq(proposedAllowed, secondAllowed, "Second proposed allowed should match");
        assertGt(secondProposedTime, firstProposedTime, "Second proposal time should be later");
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
