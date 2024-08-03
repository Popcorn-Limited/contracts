// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Owned} from "src/utils/Owned.sol";
import {IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

struct Order {
    address sellToken;
    uint256 sellAmount;
    address buyToken;
    uint256 minOut;
    uint256 timeOut;
    bool claimable;
    bool limitOrder;
    bool partialFillable;
    bytes optionalData;
}

// TODO split into storage and router
contract AsyncConverter is Owned {
    address ETH_PROXY_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    error ZeroAmount();

    constructor(address _owner) Owned(_owner) {}

    function addOrder(Order calldata order) external payable {
        // Empty order doesnt make sense
        if (order.sellAmount == 0) revert ZeroAmount();
        // Orders without slippage protection must be auctions
        if (order.minOut == 0 && order.limitOrder) revert ZeroAmount();
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
    }

    function removeOrder(uint256 id) external {
        // Option 1 not filled
        // Option 2 partely filled
        // Option 3 filled + claimable?
        // If order is entirely filled and claimable=false the last buy will remove the order
    }

    function fulfillOrder(uint256 id, uint256 amount) external {}
}
