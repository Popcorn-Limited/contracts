// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseAdapter} from "../base/BaseAdapter.sol";

contract StargateAdapter is BaseAdapter {
    function __StargateAdapter_init(
        IERC20 _underlying,
        IERC20 _lpToken,
        address _vault,
        bool _useLpToken
    ) internal onlyInitializing {
        __BaseAdapter_init(_underlying, _lpToken, _vault, _useLpToken);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        IStargateRouter(stargateRouter).addLiquidity(
            sToken.poolId(),
            amount,
            address(this)
        );
        _depositLP(lpToken.balanceOf(address(this)));
    }

    /**
     * @notice Deposits the lpToken directly into the farm
     * @dev This function is optional. Some farms might require the user to deposit lpTokens directly into the farm
     **/
    function _depositLP(uint256 amount) internal override {
        stargateStaking.deposit(stakingPid, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        uint256 lpAmount = convertToLp(amount);
        _withdrawLP(lpAmount);
        IStargateRouter(stargateRouter).removeLiquidity(
            sToken.poolId(),
            amount,
            address(this)
        );
    }

    /**
     * @notice Withdraws the lpToken directly from the farm
     * @dev This function is optional. Some farms might require the user to deposit lpTokens directly into the farm
     **/
    function _withdrawLP(uint256 amount) internal override {
        stargateStaking.withdraw(stakingPid, amount);
    }

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        return (_totalLP() * sToken.pricePerShare()) / 1e18;
    }

    /**
     * @notice Returns the total amount of lpToken
     * @dev This function is optional. Some farms might require the user to deposit lpTokens directly into the farm
     */
    function _totalLP() internal view override returns (uint256) {
        (uint256 stake, ) = stargateStaking.userInfo(stakingPid, address(this));
        return stake;
    }

    /**
     * @notice Returns the strategy’s reward tokens
     */
    function rewardToken() external view override returns (address[] memory) {
        _rewardTokens = new address[](1);
        _rewardTokens[0] = _rewardToken;
    }

    /**
     * @notice Claims rewards
     */
    function _claimRewards() internal override {
        try stargateStaking.deposit(stakingPid, 0) {
            success = true;
        } catch {}
    }
}
