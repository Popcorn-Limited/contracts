// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.0
pragma solidity ^0.8.25;

import "forge-std/console.sol";
import {AnyLBTManager} from "src/strategies/any/v2/AnyLBTManager.sol";
import {AnyConverterV2, CallStruct, ProposedChange, PendingCallAllowance} from "src/strategies/any/v2/AnyConverterV2.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, IERC20, Math} from "test/strategies/BaseStrategyTest.sol";
import {MockOracle} from "test/mocks/MockOracle.sol";
import {ILBT} from "src/interfaces/external/lfj/ILBT.sol";
import {ILBRouter} from "src/interfaces/external/lfj/ILBRouter.sol";

contract AnyLBTManagerTest is BaseStrategyTest {
    using Math for uint256;
    using stdJson for string;

    address yieldToken;
    MockOracle oracle;
    ILBRouter exchange;

    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/any/v2/AnyLBTManagerTestConfig.json"
        );
        exchange = ILBRouter(json.readAddress(".configs[0].specific.exchange"));
        oracle = new MockOracle();

        oracle.setPrice(
            json.readAddress(".configs[0].specific.tokenY"),
            testConfig.asset,
            json.readUint(".configs[0].specific.price")
        );

        _setUpBase();
    }

    function _setUpBase() internal {
        PendingCallAllowance[] memory changes = new PendingCallAllowance[](4);
        changes[0] = PendingCallAllowance({
            target: testConfig.asset,
            selector: bytes4(keccak256("approve(address,uint256)")),
            allowed: true
        });
        changes[1] = PendingCallAllowance({
            target: yieldToken,
            selector: bytes4(keccak256("approve(address,uint256)")),
            allowed: true
        });
        changes[2] = PendingCallAllowance({
            target: address(exchange),
            selector: ILBRouter.addLiquidity.selector,
            allowed: true
        });
        changes[2] = PendingCallAllowance({
            target: address(exchange),
            selector: ILBRouter.removeLiquidity.selector,
            allowed: true
        });

        AnyConverterV2(address(strategy)).proposeCallAllowance(changes);

        vm.warp(block.timestamp + 3 days + 1);
        AnyConverterV2(address(strategy)).changeCallAllowances();
    }

    function _increasePricePerShare(uint256 amount) internal override {
        deal(
            testConfig.asset,
            address(strategy),
            IERC20(testConfig.asset).balanceOf(address(strategy)) + amount
        );
    }

    function _setUpStrategy(
        string memory json_,
        string memory index_,
        TestConfig memory testConfig_
    ) internal override returns (IBaseStrategy) {
        AnyLBTManager _strategy = new AnyLBTManager();

        yieldToken = json_.readAddress(
            string.concat(".configs[", index_, "].specific.yieldToken")
        );

        _strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(yieldToken, address(oracle), uint256(0))
        );

        _strategy.setDepositIds(
            json_.readUintArray(".configs[0].specific.depositIds")
        );

        // TODO: Set up liquidity bins

        return IBaseStrategy(address(_strategy));
    }

    function _mintYieldToken(
        uint256 amount,
        address receiver
    ) internal virtual {
        vm.prank(json.readAddress(string.concat(".configs[0].specific.whale")));
        IERC20(yieldToken).transfer(receiver, amount);
    }

    function _pushFunds(uint256 amountIn, uint256 amountOut) internal {
        bytes memory encodedApprove = abi.encodeWithSelector(
            bytes4(keccak256("approve(address,uint256)")),
            address(exchange),
            amountIn
        );

        int256[] memory deltaIds = new int256[](3);
        deltaIds[0] = 0;
        deltaIds[1] = 1;
        deltaIds[2] = 2;

        uint256[] memory distributionX = new uint256[](3);
        distributionX[0] = amountIn / 5; // 20%
        distributionX[1] = (amountIn / 5) * 2; // 40%
        distributionX[2] = (amountIn / 5) * 2; // 40%

        uint256[] memory distributionY = new uint256[](3);

        bytes memory encodedSwap = abi.encodeWithSelector(
            ILBRouter.addLiquidity.selector,
            ILBRouter.LiquidityParameters({
                tokenX: json.readAddress(".configs[0].specific.tokenX"),
                tokenY: json.readAddress(".configs[0].specific.tokenY"),
                binStep: 25,
                amountX: amountIn,
                amountY: 0,
                amountXMin: 0,
                amountYMin: 0,
                activeIdDesired: 8386853,
                idSlippage: 1,
                deltaIds: deltaIds,
                distributionX: distributionX,
                distributionY: distributionY,
                to: address(this),
                refundTo: address(this),
                deadline: block.timestamp + 10_000
            })
        );

        CallStruct[] memory calls = new CallStruct[](2);
        calls[0] = CallStruct(testConfig.asset, encodedApprove);
        calls[1] = CallStruct(address(exchange), encodedSwap);

        strategy.pushFunds(0, abi.encode(calls));

        _mintAsset(amountIn, address(this));
        IERC20(testConfig.asset).approve(address(exchange), amountIn);

        // exchange.swapTokenExactAmountIn(
        //     testConfig.asset,
        //     amountIn,
        //     yieldToken,
        //     amountOut
        // );
    }

    function _pullFunds(uint256 amountIn, uint256 amountOut) internal {
        bytes memory encodedApprove = abi.encodeWithSelector(
            bytes4(keccak256("approve(address,uint256)")),
            address(exchange),
            amountIn
        );
        uint256[] memory ids = new uint256[](3);
        ids[0] = 8386854;
        ids[1] = 8386855;
        ids[2] = 8386856;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = ILBT(yieldToken).balanceOf(address(this), ids[0]);
        amounts[1] = ILBT(yieldToken).balanceOf(address(this), ids[1]);
        amounts[2] = ILBT(yieldToken).balanceOf(address(this), ids[2]);

        bytes memory encodedSwap = abi.encodeWithSelector(
            ILBRouter.removeLiquidity.selector,
            json.readAddress(".configs[0].specific.tokenX"), // tokenX
            json.readAddress(".configs[0].specific.tokenY"), // tokenY
            25, // binStep
            0, // amountXMin
            0, // amountYMin
            ids, // ids
            amounts, // amounts
            address(this), // to
            block.timestamp + 10_000 // deadline
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

    function test__pushFunds_outstanding_allowance_reverts() public {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        bytes memory encodedApprove = abi.encodeWithSelector(
            bytes4(keccak256("approve(address,uint256)")),
            address(exchange),
            testConfig.defaultAmount * 2
        );
        bytes memory encodedSwap = abi.encodeWithSelector(
            bytes4(
                keccak256(
                    "swapTokenExactAmountIn(address,uint256,address,uint256)"
                )
            ),
            testConfig.asset,
            testConfig.defaultAmount,
            yieldToken,
            testConfig.defaultAmount
        );

        CallStruct[] memory calls = new CallStruct[](2);
        calls[0] = CallStruct(testConfig.asset, encodedApprove);
        calls[1] = CallStruct(address(exchange), encodedSwap);

        vm.expectRevert("Total assets decreased");
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

    function test__pullFunds_outstanding_allowance_reverts() public {
        test__pushFunds();

        bytes memory encodedApprove = abi.encodeWithSelector(
            bytes4(keccak256("approve(address,uint256)")),
            address(exchange),
            testConfig.defaultAmount * 2
        );
        bytes memory encodedSwap = abi.encodeWithSelector(
            bytes4(
                keccak256(
                    "swapTokenExactAmountIn(address,uint256,address,uint256)"
                )
            ),
            yieldToken,
            testConfig.defaultAmount,
            testConfig.asset,
            testConfig.defaultAmount
        );

        CallStruct[] memory calls = new CallStruct[](2);
        calls[0] = CallStruct(yieldToken, encodedApprove);
        calls[1] = CallStruct(address(exchange), encodedSwap);

        vm.expectRevert("Total assets decreased");
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
                            SET ALLOWED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getProposedAllowance()
        internal
        view
        returns (PendingCallAllowance[] memory)
    {
        address target = address(0x444);
        bytes4 selector = bytes4(keccak256("someFunction(uint256)"));
        PendingCallAllowance[] memory changes = new PendingCallAllowance[](1);
        changes[0] = PendingCallAllowance({
            target: target,
            selector: selector,
            allowed: true
        });
        return changes;
    }

    function test__proposeCallAllowance() public {
        PendingCallAllowance[] memory changes = _getProposedAllowance();
        AnyConverterV2(address(strategy)).proposeCallAllowance(changes);

        (
            uint256 proposedTime,
            PendingCallAllowance[] memory proposed
        ) = AnyConverterV2(address(strategy)).getProposedCallAllowance();

        assertEq(proposed.length, 1);
        assertEq(proposed[0].selector, changes[0].selector);
        assertEq(proposed[0].target, changes[0].target);
        assertEq(proposed[0].allowed, true);
        assertEq(proposedTime, block.timestamp + 3 days);
    }

    function test__proposeCallAllowance_owner_only() public {
        PendingCallAllowance[] memory changes = _getProposedAllowance();

        vm.prank(bob);
        vm.expectRevert("Only the contract owner may perform this action");
        AnyConverterV2(address(strategy)).proposeCallAllowance(changes);
    }

    function test__proposeCallAllowance_multiple_proposal() public {
        uint256 firstCallTime = block.timestamp;
        PendingCallAllowance[] memory changes = _getProposedAllowance();
        AnyConverterV2(address(strategy)).proposeCallAllowance(changes);

        // Warp time forward
        vm.warp(block.timestamp + 1 days);

        changes[0] = PendingCallAllowance({
            target: address(0x333),
            selector: bytes4(keccak256("someOtherFunction(uint256)")),
            allowed: true
        });

        AnyConverterV2(address(strategy)).proposeCallAllowance(changes);
        (
            uint256 proposedTime,
            PendingCallAllowance[] memory proposed
        ) = AnyConverterV2(address(strategy)).getProposedCallAllowance();

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

    function test__changeCallAllowances() public {
        PendingCallAllowance[] memory changes = _getProposedAllowance();
        AnyConverterV2(address(strategy)).proposeCallAllowance(changes);

        // Warp time forward past the required delay
        vm.warp(block.timestamp + 3 days + 1);

        // Change allowances
        AnyConverterV2(address(strategy)).changeCallAllowances();

        (
            uint256 proposedTime,
            PendingCallAllowance[] memory proposed
        ) = AnyConverterV2(address(strategy)).getProposedCallAllowance();

        assertEq(proposedTime, 0);
        assertEq(proposed.length, 0);

        assertTrue(
            AnyConverterV2(address(strategy)).isAllowed(
                address(0x444),
                bytes4(keccak256("someFunction(uint256)"))
            )
        );
    }

    function test__changeCallAllowances_owner_only() public {
        PendingCallAllowance[] memory changes = _getProposedAllowance();
        AnyConverterV2(address(strategy)).proposeCallAllowance(changes);

        // Warp time forward past the required delay
        vm.warp(block.timestamp + 3 days + 1);

        vm.prank(bob);
        vm.expectRevert("Only the contract owner may perform this action");
        AnyConverterV2(address(strategy)).changeCallAllowances();
    }

    function test__changeCallAllowances_before_delay() public {
        PendingCallAllowance[] memory changes = _getProposedAllowance();
        AnyConverterV2(address(strategy)).proposeCallAllowance(changes);

        vm.expectRevert(AnyConverterV2.Misconfigured.selector);
        AnyConverterV2(address(strategy)).changeCallAllowances();
    }

    function test__changeCallAllowances_no_proposal() public {
        vm.expectRevert(AnyConverterV2.Misconfigured.selector);
        AnyConverterV2(address(strategy)).changeCallAllowances();
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
