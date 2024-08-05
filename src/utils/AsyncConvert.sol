// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Owned} from "src/utils/Owned.sol";
import {IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

struct Order {
    address sellToken;
    uint256 sellAmount;
    address buyToken;
    // limit order if maxPrice = 0 or if maxPrice == minPrice
    uint256 maxPrice;
    uint256 minPrice;
    uint256 startTime;
    uint256 timeOut;
    bool partialFillable;
    bytes optionalData;
}

// TODO split into storage and router
contract AsyncConverter is Owned {
    address ETH_PROXY_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    error ZeroAmount();

    uint256 totalOrders;
    mapping(uint256 => Order) public orders;

    constructor(address _owner) Owned(_owner) {}

    function addOrder(Order calldata order) external payable {
        // Empty order doesnt make sense
        if (order.sellAmount == 0) revert ZeroAmount();
        // Protect from wrong price settings
        if (
            (order.minPrice == 0 && order.maxPrice == 0) ||
            order.maxPrice < order.minPrice
        ) revert ZeroAmount();
        // Make sure enough eth have been send if used as sell token
        if (
            order.sellToken == ETH_PROXY_ADDRESS && msg.value < order.sellAmount
        ) revert ZeroAmount();

        // Adjust maxPrice for limit orders
        if (order.maxPrice == 0) order.maxPrice = order.minPrice;

        // Adjust startTime if not set
        if (order.startTime == 0) order.startTime = block.timestamp;

        if (order.sellToken != ETH_PROXY_ADDRESS)
            IERC20(order.sellToken).transferFrom(
                msg.sender,
                address(this),
                order.sellAmount
            );

        uint256 orderId = totalOrders + 1;
        orders[orderId] = order;
    }

    function removeOrder(uint256 id) external {
        // Option 1 not filled
        // Option 2 partely filled
        // Option 3 filled + claimable?
        // If order is entirely filled and claimable=false the last buy will remove the order
    }

    function fulfillOrderPreciseIn(
        uint256 id,
        uint256 buyAmount
    ) external payable {
        Order memory order = orders[id];

        // Order doesnt exist
        if (order.startTime == 0) revert ZeroAmount();
        // Order is over
        if (order.timeOut >= block.timestamp) revert ZeroAmount();

        uint256 sellAmount = buyAmount / price;

        // Buying more than are offered
        if (sellAmount > order.sellAmount) revert ZeroAmount();

        if (order.partialFillable) {
            // Order needs be filled whole
            if (sellAmount < order.sellAmount) revert ZeroAmount();
            
        } else {}

        IERC20(order.buyToken).transferFrom(
            msg.sender,
            address(this),
            buyAmount
        );
        IERC20(order.sellToken).transfer(msg.sender, sellAmount);
    }

    function fulfillOrderPreciseOut(
        uint256 id,
        uint256 sellAmount
    ) external payable {
        Order memory order = orders[id];

        // Order doesnt exist
        if (order.startTime == 0) revert ZeroAmount();
        // Order is over
        if (order.timeOut >= block.timestamp) revert ZeroAmount();
        // Buying more than are offered
        if (sellAmount > order.sellAmount) revert ZeroAmount();

        if (order.partialFillable) {
            // Order needs be filled whole
            if (sellAmount < order.sellAmount) revert ZeroAmount();
        } else {}

        uint256 buyAmount = sellAmount * price;

        IERC20(order.buyToken).transferFrom(
            msg.sender,
            address(this),
            buyAmount
        );
        IERC20(order.sellToken).transfer(msg.sender, sellAmount);
    }
}
