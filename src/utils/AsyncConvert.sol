// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Owned} from "src/utils/Owned.sol";
import {IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

struct Order {
    address owner;
    address sellToken;
    uint256 sellAmount;
    address buyToken;
    // Should be 0 and will be set to 0 on creation
    uint256 buyAmount;
    // Limit order if decayPerSec == 0
    uint256 decayPerSec;
    uint256 minPrice;
    uint256 endTime;
    bool partialFillable;
    bytes optionalData;
}

// TODO split into storage and router ?
contract AsyncConverter is Owned {
    address ETH_PROXY_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 totalOrders;
    mapping(uint256 => Order) public orders;

    event OrderAdded(uint256 id, Order order);
    event OrderRemoved(uint256 id, Order order);
    event OrderFilled(
        uint256 id,
        uint256 buyAmount,
        uint256 sellAmount,
        uint256 price
    );

    error ZeroAmount();

    constructor(address _owner) Owned(_owner) {}

    function addOrder(Order calldata order) external payable {
        // No zero addresses
        if (
            order.sellToken == address(0) ||
            order.buyToken == address(0) ||
            order.owner == address(0)
        ) revert ZeroAmount();
        // Empty order doesnt make sense
        if (order.sellAmount == 0) revert ZeroAmount();
        // Protect from wrong price settings
        if (order.minPrice == 0 && order.decayPerSec == 0) revert ZeroAmount();

        if (order.sellToken == ETH_PROXY_ADDRESS) {
            // Make sure enough eth have been send if used as sell token
            if (msg.value != order.sellAmount) revert ZeroAmount();
        } else {
            IERC20(order.sellToken).transferFrom(
                msg.sender,
                address(this),
                order.sellAmount
            );
        }

        // Adjust buyAmount if > 0
        if (order.buyAmount != 0) order.buyAmount = 0;

        uint256 orderId = totalOrders + 1;
        orders[orderId] = order;

        emit OrderAdded(orderId, order);
    }

    function removeOrder(uint256 id) external {
        Order memory order = orders[id];

        // Only the order-owner can remove orders
        if (order.owner != msg.sender) revert ZeroAmount();

        // Refund unused sell tokens
        if (order.sellAmount > 0) {
            if (order.sellToken == ETH_PROXY_ADDRESS) {
                (bool success, ) = order.owner.call{value: order.sellAmount}(
                    ""
                );
                if (!success) revert ZeroAmount();
            } else {
                IERC20(order.sellToken).transfer(order.owner, order.sellAmount);
            }
        }

        // Cash out buy tokens
        if (order.buyAmount > 0) {
            if (order.buyToken == ETH_PROXY_ADDRESS) {
                (bool success, ) = order.owner.call{value: order.buyAmount}("");
                if (!success) revert ZeroAmount();
            } else {
                IERC20(order.buyToken).transfer(order.owner, order.buyAmount);
            }
        }

        delete orders[id];

        emit OrderRemoved(id, order);
    }

    function fulfillOrderPreciseIn(
        uint256 id,
        uint256 buyAmount
    ) external payable {
        Order memory order = orders[id];

        // Order doesnt exist
        if (order.endTime == 0) revert ZeroAmount();
        // Order is over
        if (order.endTime >= block.timestamp) revert ZeroAmount();

        uint256 price = _getOrderPrice(order);
        uint256 sellAmount = buyAmount / price;

        // Buying more than are offered
        if (sellAmount > order.sellAmount) revert ZeroAmount();

        // Order needs be filled whole
        if (!order.partialFillable && sellAmount < order.sellAmount)
            revert ZeroAmount();

        if (order.buyToken == ETH_PROXY_ADDRESS) {
            // Make sure enough eth have been send if used as buy token
            if (msg.value != buyAmount) revert ZeroAmount();
        } else {
            IERC20(order.buyToken).transferFrom(
                msg.sender,
                address(this),
                buyAmount
            );
        }

        IERC20(order.sellToken).transfer(msg.sender, sellAmount);

        order.sellAmount -= sellAmount;
        order.buyAmount += buyAmount;

        emit OrderFilled(id, buyAmount, sellAmount, price);
    }

    function fulfillOrderPreciseOut(
        uint256 id,
        uint256 sellAmount
    ) external payable {
        Order memory order = orders[id];

        // Order doesnt exist
        if (order.endTime == 0) revert ZeroAmount();
        // Order is over
        if (order.endTime >= block.timestamp) revert ZeroAmount();
        // Buying more than are offered
        if (sellAmount > order.sellAmount) revert ZeroAmount();

        // Order needs be filled whole
        if (!order.partialFillable && sellAmount < order.sellAmount)
            revert ZeroAmount();

        uint256 price = _getOrderPrice(order);
        uint256 buyAmount = sellAmount * price;

        if (order.buyToken == ETH_PROXY_ADDRESS) {
            // Make sure enough eth have been send if used as buy token
            if (msg.value != buyAmount) revert ZeroAmount();
        } else {
            IERC20(order.buyToken).transferFrom(
                msg.sender,
                address(this),
                buyAmount
            );
        }

        IERC20(order.sellToken).transfer(msg.sender, sellAmount);

        order.sellAmount -= sellAmount;
        order.buyAmount += buyAmount;

        emit OrderFilled(id, buyAmount, sellAmount, price);
    }

    function getOrderPrice(uint256 id) public view returns (uint256) {
        Order memory order = orders[id];
        // Order doesnt exist
        if (order.endTime == 0) revert ZeroAmount();
        // Order is over
        if (order.endTime >= block.timestamp) revert ZeroAmount();

        return _getOrderPrice(order);
    }

    function _getOrderPrice(
        Order memory order
    ) internal view returns (uint256) {
        if (order.decayPerSec == 0) return order.minPrice;

        uint256 timeDiff = order.endTime - block.timestamp;

        return order.minPrice + (timeDiff * decayPerSec);
    }
}
