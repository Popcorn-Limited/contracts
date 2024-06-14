// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "src/strategies/BaseStrategy.sol";
import {IStakedToken, IPoolRewards} from "./IPeapods.sol";

/**
 * @title   ERC4626 Peapods Finance Vault Adapter
 * @author  ADN
 * @notice  ERC4626 wrapper for Peapods protocol
 *
 * Receives Peapods Camelot-LP tokens and stakes them for extra rewards.
 * Claim and compound the rewards into more LP tokens
 */
contract PeapodsDepositor is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IStakedToken public stakedToken; // vault holding after deposit
    IPoolRewards public poolRewards; // pool to get rewards from

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoDeposit_ Controls if `protocolDeposit` gets called on deposit
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function initialize(address asset_, address owner_, bool autoDeposit_, bytes memory strategyInitData_)
        external
        virtual
        initializer
    {
        __PeapodsBase_init(asset_, owner_, autoDeposit_, strategyInitData_);
    }

    function __PeapodsBase_init(address asset_, address owner_, bool autoDeposit_, bytes memory strategyInitData_)
        internal
        onlyInitializing
    {
        // asset is LP token
        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        _name = string.concat("VaultCraft Peapods ", IERC20Metadata(asset_).name(), " Adapter");
        _symbol = string.concat("vcp-", IERC20Metadata(asset_).symbol());

        // validate staking contract
        (address staking_) = abi.decode(strategyInitData_, (address));
        stakedToken = IStakedToken(staking_);

        if (stakedToken.stakingToken() != asset_) {
            revert InvalidAsset();
        }

        poolRewards = IPoolRewards(stakedToken.poolRewards());

        // approve peapods staking contract
        IERC20(asset_).approve(staking_, type(uint256).max);
    }

    function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _name;
    }

    function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function _totalAssets() internal view override returns (uint256 t) {
        // return balance of staked tokens -> 1:1 with LP token
        return IERC20(address(stakedToken)).balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim liquidity mining rewards given that it's active
    function claim() internal override returns (bool success) {
        try poolRewards.claimReward(address(this)) {
            success = true;
        } catch {}
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 amount, uint256, bytes memory) internal override {
        // stake lp tokens
        stakedToken.stake(address(this), amount);
    }

    function _protocolWithdraw(uint256 amount, uint256, bytes memory) internal override {
        // unstake lp tokens
        stakedToken.unstake(amount);
    }
}
