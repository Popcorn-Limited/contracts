// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC7540Redeem} from "ERC-7540/interfaces/IERC7540.sol";

interface IAsyncVault is IERC7540Redeem {
    function fulfillRedeem(
        uint256 shares,
        address controller
    ) external returns (uint256 total);

    function fulfillMultipleRedeems(
        uint256[] memory shares,
        address[] memory controllers
    ) external returns (uint256 total);
}
