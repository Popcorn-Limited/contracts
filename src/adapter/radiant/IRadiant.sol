// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.15;

import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

// Radiant rToken (wrapped underlying)
interface IRToken is IERC20 {
    /**
     * @dev Returns the address of the underlying asset of this rToken (E.g. WETH for rWETH)
     **/
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

// Radiant lending pool interface
interface ILendingPool {
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

// Radiant protocol data provider
interface IProtocolDataProvider {
    function getReserveTokensAddresses(
        address asset
    )
        external
        view
        returns (
            address rTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress
        );
}

interface IIncentivesController {
    function claimAll(address _user) external;
}
