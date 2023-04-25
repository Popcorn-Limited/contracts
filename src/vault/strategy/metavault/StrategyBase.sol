// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IWithRewards} from "../../../interfaces/vault/IWithRewards.sol";
import {IEIP165} from "../../../interfaces/IEIP165.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IUniswapRouterV2} from "../../../interfaces/external/uni/IUniswapRouterV2.sol";
import {IAdapter} from "../../../interfaces/vault/IAdapter.sol";
import {IWithRewards} from "../../../interfaces/vault/IWithRewards.sol";

contract StrategyBase {
    // Native token on chain
    address public native;

    // Struct for ProtocolAddress. Specifies an address and its description in bytes for internal use in vault.
    struct ProtocolAddress {
        address addr;
        bytes desc;
    }

    // Struct for ProtocolUint. Specifies a uint256 and its description in bytes for internal use in vault.
    struct ProtocolUint {
        uint256 num;
        bytes desc;
    }

    // Protocol contracts info (masterchefs, poolIds, gaugeAddresses, etc.)
    // These arrays can be used however the strategist would like to store data.
    //
    // As an example for protocolUints could be: indexes 0-4 used for disparate pieces of information,
    // index 5 holds the length of the proceeding values, and indexes 6+ can hold the additional values for which
    // index 5 holds the total length of (i.e. an indefinite number of gauges, pids, etc).
    // If any values are altered, the strategist would have to ensure that the length uint at index 5 has
    // been properly updated respectively.
    //
    // While any pertinent values can be stored in protocolAddresses and protocolUints,
    // it is important for the strategist to devise an organized and extensible system to properly
    // operate their strategy in a durable manner using the alloted arrays on their own behalf. Be careful.
    ProtocolAddress[] public protocolAddresses;
    ProtocolUint[] public protocolUints;

    // Vault and Strategist
    address public vault;
    address public strategist;

    // Swapping
    address[] public tradeModules;
    address[] public routers;
    /**
     * @dev rewardToken index must match respective index in rewardRoutes and pendingRewards.
     * @dev Routes follow this pattern: [rewardToken, ...hops, native]
     */
    address[][] public rewardsToNativeRoutes;

    // Data management
    bool public isVaultFunctional;
    uint256 public lastHarvest;
    address[] public rewardTokens;
    uint256[] public pendingRewards;

    // Events
    event Harvest();

    // Errors
    error InvalidRoute();
    error FunctionNotImplemented(bytes4 sig);

    function verifyAdapterSelectorCompatibility(bytes4[8] memory sigs) public {
        uint8 len = uint8(sigs.length);
        for (uint8 i; i < len; i++) {
            if (sigs[i].length == 0) return;
            if (!IEIP165(address(this)).supportsInterface(sigs[i]))
                revert FunctionNotImplemented(sigs[i]);
        }
    }

    function verifyAdapterCompatibility(bytes memory data) public virtual {}

    /*//////////////////////////////////////////////////////////////
                          MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reset vault functionality bool upon changing internal data (contract addressess, routes, pids, etc).
    modifier vaultCheck() {
        _;

        if (isVaultFunctional == true) isVaultFunctional = false;
    }

    /*//////////////////////////////////////////////////////////////
                          SETUP
    //////////////////////////////////////////////////////////////*/

    // Give allowances necessary for deposit, withdraw, lpToken swaps, and addLiquidity.
    function _giveAllowances() internal virtual {}

    // Give allowances for rewardToken swaps.
    function giveRewardAllowances() public {
        address swapRouter = routers[0];

        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; ++i) {
            ERC20(rewardTokens[i]).approve(swapRouter, type(uint256).max);
        }
    }

    // Give initial allowances for setup.
    function _giveInitialAllowances() internal {
        _giveAllowances();
        giveRewardAllowances();
    }

    /*//////////////////////////////////////////////////////////////
                          HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    // Harvest rewards.
    function harvest() public virtual {
        if (_rewardsCheck() == true && _rewardRoutesCheck() == true) {
            _compound();
        }

        lastHarvest = block.timestamp;

        if (isVaultFunctional == false) isVaultFunctional = true;

        emit Harvest();
    }

    // Logic to claim rewards, swap rewards to native, charge fees, swap native to deposit token, add liquidity (if necessary), and re-deposit.
    function _compound() internal virtual {}

    // Swap all rewards to native token.
    function _swapRewardsToNative() internal virtual {
        uint256 len = rewardsToNativeRoutes.length;
        for (uint256 i; i < len; ++i) {
            address reward = rewardsToNativeRoutes[i][0];
            address[] memory rewardRoute = rewardsToNativeRoutes[i];
            uint256 rewardAmount = ERC20(reward).balanceOf(address(this));
            if (rewardAmount > 0) {
                _swapRewardsToNative(rewardRoute, rewardAmount);
            }
        }
    }

    function _swapRewardsToNative(
        address[] memory _rewardRoute,
        uint256 rewardAmount
    ) internal virtual {}

    // Claim rewards from underlying protocol.
    function _claimRewards() internal virtual {
        IWithRewards(address(this)).claim();
    }

    // Deposit assetToken or lpPair into underlying protocol.
    function _deposit() internal virtual {
        uint256 assets = 1e18;
        uint256 shares = 1e18;

        IAdapter(address(this)).strategyDeposit(assets, shares);

        // _onDeposit(assets, shares);
    }

    // // Specify functionality of _deposit after IAdapter(address(this)).strategyDeposit(assets, shares);.
    // function _onDeposit(uint256 _assets, uint256 _shares) internal virtual {}

    /*//////////////////////////////////////////////////////////////
                          REWARDS AND ROUTES
    //////////////////////////////////////////////////////////////*/

    // Return available rewards for all rewardTokens.
    function rewardsAvailable() public virtual returns (uint256[] memory) {}

    // Set rewards tokens according to rewardToNativeRoutes.
    function _setRewardTokens(
        address[][] memory _rewardsToNativeRoutes
    ) internal virtual {
        uint256 len = _rewardsToNativeRoutes.length;
        for (uint256 i; i < len; ++i) {
            if (
                _rewardsToNativeRoutes[i][_rewardsToNativeRoutes.length - 1] !=
                native
            ) revert InvalidRoute();
            rewardTokens[i] = _rewardsToNativeRoutes[i][0];
        }
    }

    // Check to see that at least 1 reward is available.
    function _rewardsCheck() internal virtual returns (bool) {
        pendingRewards = rewardsAvailable();

        uint256 len = pendingRewards.length;
        for (uint256 i; i < len; ++i) {
            if (pendingRewards[i] > 0) {
                return true;
            }
        }

        return false;
    }

    // Check to make sure all rewardTokens have correct respective routes.
    function _rewardRoutesCheck() internal view virtual returns (bool) {
        uint256 len = rewardTokens.length;

        for (uint256 i; i < len; ++i) {
            if (
                rewardTokens[i] != rewardsToNativeRoutes[i][0] ||
                native !=
                rewardsToNativeRoutes[i][rewardsToNativeRoutes.length - 1]
            ) return false;
        }

        return true;
    }

    // Set all rewardRoutes.
    function setAllRewardsToNativeRoutes(
        address[][] memory _routes
    ) public virtual vaultCheck {
        rewardsToNativeRoutes = _routes;
    }

    // Set rewardRoute at index.
    function setRewardsToNativeRoute(
        uint256 _rewardIndex,
        address[] memory _route
    ) public virtual vaultCheck {
        rewardsToNativeRoutes[_rewardIndex] = _route;
    }

    // Get rewardRoute at index.
    function getRewardsToNativeRoute(
        uint256 _rewardIndex
    ) public view virtual returns (address[] memory) {
        return rewardsToNativeRoutes[_rewardIndex];
    }

    /*//////////////////////////////////////////////////////////////
                          DATA MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    // Set all protocolAddresses.
    function setAllProtocolAddresses(
        ProtocolAddress[] memory _protocolAddresses
    ) public vaultCheck {
        for (uint i; i < _protocolAddresses.length; ++i) {
            protocolAddresses[i] = _protocolAddresses[i];
        }
    }

    // Set protocolAddress at index.
    function setProtocolAddress(
        ProtocolAddress memory _address,
        uint256 _idx
    ) public vaultCheck {
        protocolAddresses[_idx] = _address;
    }

    // Get a value on protocolAddress at index.
    function getProtocolAddress(
        uint256 _idx
    ) public view returns (ProtocolAddress memory) {
        return protocolAddresses[_idx];
    }

    // Set all protocolUints.
    function setAllProtocolUints(
        ProtocolUint[] memory _protocolUints
    ) public vaultCheck {
        for (uint i; i < _protocolUints.length; ++i) {
            protocolUints[i] = _protocolUints[i];
        }
    }

    // Set protocolUints at index.
    function setProtocolUint(
        ProtocolUint memory _uint,
        uint256 _idx
    ) public vaultCheck {
        protocolUints[_idx] = _uint;
    }

    // Get a value on protocolUint at index.
    function getProtocolUint(
        uint256 _idx
    ) public view returns (ProtocolUint memory) {
        return protocolUints[_idx];
    }

    /*//////////////////////////////////////////////////////////////
                          ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    // Calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view virtual returns (uint256) {}

    // Calculates how much 'want' this contract holds.
    function balanceOfWant() public view virtual returns (uint256) {}

    // Calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view virtual returns (uint256) {}
}
