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
    // Limit order if maxPrice = 0 or if maxPrice == minPrice
    uint256 maxPrice;
    uint256 minPrice;
    uint256 startTime;
    uint256 endTime;
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

                // Adjust maxPrice for limit orders
        if (order.maxPrice == 0) order.maxPrice = order.minPrice;

        // Adjust startTime if not set
        if (order.startTime == 0) order.startTime = block.timestamp;


        // Make sure enough eth have been send if used as sell token
        if (
            order.sellToken == ETH_PROXY_ADDRESS && msg.value < order.sellAmount
        ) revert ZeroAmount();


        if (order.sellToken != ETH_PROXY_ADDRESS)
            IERC20(order.sellToken).transferFrom(
                msg.sender,
                address(this),
                order.sellAmount
            );

        order.buyAmount = 0;

        uint256 orderId = totalOrders + 1;
        orders[orderId] = order;

        // TODO - add event
    }

    function removeOrder(uint256 id) external {
        Order memory order = orders[id];

        if (order.owner != msg.sender) revert ZeroAmount();

        // Refund unused sell tokens
        if (order.sellAmount > 0)
            IERC20(order.sellToken).transfer(order.owner, order.sellAmount);

        // Cash out buy tokens
        if (order.buyAmount > 0)
            IERC20(order.buyToken).transfer(order.owner, order.buyAmount);

        delete orders[id]

        // TODO - add event
    }

    function fulfillOrderPreciseIn(
        uint256 id,
        uint256 buyAmount
    ) external payable {
        Order memory order = orders[id];

        // Order doesnt exist
        if (order.startTime == 0) revert ZeroAmount();
        // Order is over
        if (order.endTime >= block.timestamp) revert ZeroAmount();

        // TODO - add price function
        uint256 sellAmount = buyAmount / price;

        // Buying more than are offered
        if (sellAmount > order.sellAmount) revert ZeroAmount();

        if (order.partialFillable) {} else {
            // Order needs be filled whole
            if (sellAmount < order.sellAmount) revert ZeroAmount();
        }
    	
        if (
            order.buyToken == ETH_PROXY_ADDRESS) {
                if(msg.value < order.buyAmount) revert ZeroAmount();
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

        // TODO - add event
    }

    function fulfillOrderPreciseOut(
        uint256 id,
        uint256 sellAmount
    ) external payable {
        Order memory order = orders[id];

        // Order doesnt exist
        if (order.startTime == 0) revert ZeroAmount();
        // Order is over
        if (order.endTime >= block.timestamp) revert ZeroAmount();
        // Buying more than are offered
        if (sellAmount > order.sellAmount) revert ZeroAmount();

        if (order.partialFillable) {} else {
            // Order needs be filled whole
            if (sellAmount < order.sellAmount) revert ZeroAmount();
        }

        // TODO - add price function
        uint256 buyAmount = sellAmount * price;

        IERC20(order.buyToken).transferFrom(
            msg.sender,
            address(this),
            buyAmount
        );
        IERC20(order.sellToken).transfer(msg.sender, sellAmount);

        order.sellAmount -= sellAmount;
        order.buyAmount += buyAmount;

        // TODO - add event
    }

    function price(uint256 id) public view returns (uint256){
                Order memory order = orders[id];
                        // Order doesnt exist
        if (order.startTime == 0) revert ZeroAmount();
        // Order is over

                        if(order.endTime >= block.timestamp) revert ZeroAmount();


    }

    function _price(Order memory order) internal view returns (uint256){
        uint256 timeDiff = block.timestamp - order.startTime;
        uint256 decayPerSec = order.endTime - order.startTime;
        return 0;
    }
}
