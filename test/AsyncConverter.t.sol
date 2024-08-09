// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test, console} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {AsyncConverter, Order} from "src/utils/AsyncConverter.sol";

contract AsyncConverterTest is Test {
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 wbtc = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    address ETH_PROXY_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address bob = address(0x1111);
    address alice = address(0x2222);

    AsyncConverter converter;
    Order order;

    event OrderAdded(uint256 id, Order order);
    event OrderRemoved(uint256 id, Order order);
    event OrderFilled(
        uint256 id,
        uint256 buyAmount,
        uint256 sellAmount,
        uint256 price
    );

    error ZeroAmount();

    /*//////////////////////////////////////////////////////////////
                              SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        converter = new AsyncConverter(address(this));
        order = Order({
            owner: bob,
            sellToken: address(weth),
            sellAmount: 1e18,
            buyToken: address(usdc),
            buyAmount: 0,
            decayPerSec: 0,
            minPrice: 1000e6,
            endTime: block.timestamp + 1000,
            partialFillable: true,
            optionalData: ""
        });
    }

    /*//////////////////////////////////////////////////////////////
                              HELPER
    //////////////////////////////////////////////////////////////*/

    function _addOrder() internal {
        deal(address(weth), bob, 1e18);

        vm.startPrank(bob);
        weth.approve(address(converter), 1e18);
        converter.addOrder(order);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              ADD ORDER
    //////////////////////////////////////////////////////////////*/

    function test__addOrder() public {
        deal(address(weth), bob, 1.5e18);

        vm.startPrank(bob);
        weth.approve(address(converter), 2e18);

        vm.expectEmit(true, true, false, true);
        emit OrderAdded(0, order);
        converter.addOrder(order);

        assertEq(weth.balanceOf(address(converter)), 1e18);
        assertEq(weth.balanceOf(bob), 0.5e18);

        Order memory createdOrder = converter.orders(0);
        assertEq(createdOrder.owner, bob);
        assertEq(createdOrder.sellToken, address(weth));
        assertEq(createdOrder.buyToken, address(usdc));
        assertEq(createdOrder.sellAmount, 1e18);

        // Add second order
        order.endTime = block.timestamp + 1000;
        order.sellAmount = 0.5e18;

        vm.expectEmit(true, true, false, true);
        emit OrderAdded(1, order);
        converter.addOrder(order);

        assertEq(weth.balanceOf(address(converter)), 1.5e18);
        assertEq(weth.balanceOf(bob), 0);

        createdOrder = converter.orders(1);
        assertEq(createdOrder.owner, bob);
        assertEq(createdOrder.sellToken, address(weth));
        assertEq(createdOrder.buyToken, address(usdc));
        assertEq(createdOrder.sellAmount, 0.5e18);

        // remove order and readd it
        // (orders shouldnt be overriden and totalOrders should simply increase)
        converter.removeOrder(1);

        order.endTime = block.timestamp + 1000;

        vm.expectEmit(true, true, false, true);
        emit OrderAdded(2, order);
        converter.addOrder(order);

        assertEq(weth.balanceOf(address(converter)), 1.5e18);
        assertEq(weth.balanceOf(bob), 0);

        // Order 1 should now be deleted
        createdOrder = converter.orders(1);
        assertEq(createdOrder.owner, address(0));
        assertEq(createdOrder.sellToken, address(0));
        assertEq(createdOrder.buyToken, address(0));
        assertEq(createdOrder.sellAmount, 0);

        createdOrder = converter.orders(2);
        assertEq(createdOrder.owner, bob);
        assertEq(createdOrder.sellToken, address(weth));
        assertEq(createdOrder.buyToken, address(usdc));
        assertEq(createdOrder.sellAmount, 0.5e18);
    }

    function test__addOrder_with_eth() public {
        deal(bob, 1e18);

        order.sellToken = ETH_PROXY_ADDRESS;

        vm.startPrank(bob);

        vm.expectEmit(true, true, false, true);
        emit OrderAdded(0, order);
        converter.addOrder{value: 1e18}(order);

        Order memory createdOrder = converter.orders(0);

        assertEq(address(converter).balance, 1e18);
        assertEq(bob.balance, 0);

        assertEq(createdOrder.owner, bob);
        assertEq(createdOrder.sellToken, ETH_PROXY_ADDRESS);
        assertEq(createdOrder.buyToken, address(usdc));
    }

    function test__addOrder_for_someone_else() public {
        deal(address(weth), address(this), 1e18);

        weth.approve(address(converter), 1e18);

        vm.expectEmit(true, true, false, true);
        emit OrderAdded(0, order);
        converter.addOrder(order);

        Order memory createdOrder = converter.orders(0);

        assertEq(weth.balanceOf(address(converter)), 1e18);
        assertEq(weth.balanceOf(address(this)), 0);
        assertEq(weth.balanceOf(bob), 0);

        assertEq(createdOrder.owner, bob);
        assertEq(createdOrder.sellToken, address(weth));
        assertEq(createdOrder.buyToken, address(usdc));
    }

    function test__addOrder_no_zeroAddress() public {
        order.sellToken = address(0);

        vm.expectRevert(AsyncConverter.ZeroAddress.selector);
        converter.addOrder(order);

        order.sellToken = address(weth);
        order.owner = address(0);

        vm.expectRevert(AsyncConverter.ZeroAddress.selector);
        converter.addOrder(order);

        order.owner = address(this);
        order.buyToken = address(0);

        vm.expectRevert(AsyncConverter.ZeroAddress.selector);
        converter.addOrder(order);
    }

    function test__addOrder_no_zeroAmount() public {
        order.sellAmount = 0;

        vm.expectRevert(AsyncConverter.ZeroAmount.selector);
        converter.addOrder(order);
    }

    function test__addOrder_no_zeroPrice() public {
        order.minPrice = 0;

        vm.expectRevert(AsyncConverter.ZeroPrice.selector);
        converter.addOrder(order);
    }

    function test__addOrder_no_end_in_the_past() public {
        order.endTime = 0;

        vm.expectRevert(AsyncConverter.TimeOut.selector);
        converter.addOrder(order);
    }

    function test__addOrder_insufficient_amount() public {
        order.sellToken = ETH_PROXY_ADDRESS;

        vm.expectRevert(AsyncConverter.InsufficientAmount.selector);
        converter.addOrder(order);
    }

    /*//////////////////////////////////////////////////////////////
                        FULFILL ORDER PRECISE IN
    //////////////////////////////////////////////////////////////*/

    function test__fulfillOrderPreciseIn() public {
        _addOrder();

        deal(address(usdc), alice, 2000e6);
    }

    function test__fulfillOrderPreciseIn_eth() public {
        _addOrder();

        deal(address(usdc), alice, 2000e6);
    }

    function test__fulfillOrderPreciseIn_sellAmount_larger_than_order()
        public
    {}

    function test__fulfillOrderPreciseIn_no_order() public {
        vm.expectRevert(AsyncConverter.NoOrder.selector);
        converter.fulfillOrderPreciseIn(0, 10e18);
    }

    function test__fulfillOrderPreciseIn_order_is_over() public {
        _addOrder();

        vm.skip(1000);

        vm.expectRevert(AsyncConverter.TimeOut.selector);
        converter.fulfillOrderPreciseIn(0, 10e18);
    }

    function test__fulfillOrderPreciseIn_not_partialFillable_sellAmount_too_small()
        public
    {
        order.partialFillable = false;
        _addOrder();

        vm.expectRevert(AsyncConverter.InsufficientAmount.selector);
        converter.fulfillOrderPreciseIn(0, 1e17);
    }

    function test__addOrder_insufficient_amount() public {
        order.buyToken = ETH_PROXY_ADDRESS;
        _addOrder();

        vm.expectRevert(AsyncConverter.InsufficientAmount.selector);
        converter.fulfillOrderPreciseIn(0, 1e17);
    }

    /*//////////////////////////////////////////////////////////////
                        FULFILL ORDER PRECISE OUT
    //////////////////////////////////////////////////////////////*/

    function test__fulfillOrderPreciseOut() public {}

    function test__fulfillOrderPreciseOut_no_order() public {}

    function test__fulfillOrderPreciseOut_order_is_over() public {}

    function test__fulfillOrderPreciseOut_sellAmount_too_large() public {}

    function test__fulfillOrderPreciseOut_not_partialFillable_sellAmount_too_small()
        public
    {}

    function test__fulfillOrderPreciseOut_no_zeroAmount() public {}

    /*//////////////////////////////////////////////////////////////
                            REMOVE ORDER
    //////////////////////////////////////////////////////////////*/

    function test__removeOrder() public {
        _addOrder();

        vm.startPrank(bob);

        vm.expectEmit(true, true, false, true);
        emit OrderRemoved(0, order);
        converter.removeOrder(0);

        // SellToken was refunded to owner
        assertEq(weth.balanceOf(address(converter)), 0);
        assertEq(weth.balanceOf(bob), 1e18);

        // Order was deleted
        Order memory createdOrder = converter.orders(0);
        assertEq(createdOrder.endTime, 0);
    }

    function test__removeOrder_fulfilled() public {
        _addOrder();

        vm.startPrank(bob);

        vm.expectEmit(true, true, false, true);
        emit OrderRemoved(0, order);
        converter.removeOrder(0);

        // SellToken was refunded to owner
        assertEq(weth.balanceOf(address(converter)), 0);
        assertEq(weth.balanceOf(bob), 1e18);

        // Order was deleted
        Order memory createdOrder = converter.orders(0);
        assertEq(createdOrder.endTime, 0);
    }

    function test__removeOrder_not_owner() public {
        _addOrder();

        // Non-owner cant remove the order before timeout
        vm.expectRevert(AsyncConverter.NotOwner.selector);
        converter.removeOrder(0);

        vm.skip(1001);

        // Anyone can remove the order after timeout
        vm.expectEmit(true, true, false, true);
        emit OrderRemoved(0, order);
        converter.removeOrder(0);

        // SellToken was refunded to owner
        assertEq(weth.balanceOf(address(converter)), 0);
        assertEq(weth.balanceOf(address(this)), 0);
        assertEq(weth.balanceOf(bob), 1e18);

        // Order was deleted
        Order memory createdOrder = converter.orders(0);
        assertEq(createdOrder.endTime, 0);
    }

    function test__removeOrder_no_order() public {
        vm.expectRevert(AsyncConverter.NoOrder.selector);
        converter.removeOrder(0);
    }

    /*//////////////////////////////////////////////////////////////
                            GET ORDER PRICE
    //////////////////////////////////////////////////////////////*/

    function test__getOrderPrice() public {
        order.decayPerSec = 1e6;
        _addOrder();

        uint256 price = converter.getOrderPrice(0);
        assertEq(price, 2000e6);

        vm.skip(100);
        price = converter.getOrderPrice(0);
        assertEq(price, 1900e6);

        vm.skip(899);
        price = converter.getOrderPrice(0);
        assertEq(price, 1001e6);
    }

    function test__getOrderPrice_limitPrice() public {
        _addOrder();

        uint256 price = converter.getOrderPrice(0);
        assertEq(price, 1000e6);

        vm.skip(100);
        price = converter.getOrderPrice(0);
        assertEq(price, 1000e6);

        vm.skip(899);
        price = converter.getOrderPrice(0);
        assertEq(price, 1000e6);
    }

    function test__getOrderPrice_no_order() public {
        vm.expectRevert(AsyncConverter.NoOrder.selector);
        converter.getOrderPrice(0);
    }

    function test__getOrderPrice_order_over() public {
        _addOrder();

        vm.skip(1001);

        vm.expectRevert(AsyncConverter.TimeOut.selector);
        converter.getOrderPrice(0);
    }

    /*//////////////////////////////////////////////////////////////
                           EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test__decimal_conversions() public {
        // selling 0.001 $ USDC for BTC
        // selling 0.001 $ BTC for USDC
        // 27 decimal token vs 2 decimal token
    }

    function test__problematic_decay_plus_timeDiff() public {
        // ?
    }
}
