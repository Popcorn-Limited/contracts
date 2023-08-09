// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseAdapter, IERC20} from "../base/BaseAdapter.sol";
import {ISToken, IStargateStaking, IStargateRouter} from "../../adapter/stargate/IStargate.sol";

contract StargateAdapter is BaseAdapter {
    uint256 internal stakingPid;

    /// @notice The Stargate LpStaking contract
    IStargateStaking internal stargateStaking;
    ISToken internal sToken;
    IStargateRouter internal stargateRouter;

    // TODO add fallback for eth

    error StakingIdOutOfBounds();
    error DifferentAssets();

    function __StargateAdapter_init(
        IERC20 _underlying,
        IERC20 _lpToken,
        bool _useLpToken,
        IERC20[] memory _rewardTokens,
        address registry,
        bytes memory stargateInitData
    ) internal onlyInitializing {
        __BaseAdapter_init(_underlying, _lpToken, _useLpToken, _rewardTokens);

        (uint256 _stakingPid, address _stargateRouter) = abi.decode(
            stargateInitData,
            (uint256, address)
        );

        stargateStaking = IStargateStaking(registry);
        if (_stakingPid >= stargateStaking.poolLength())
            revert StakingIdOutOfBounds();

        stakingPid = _stakingPid;
        stargateRouter = IStargateRouter(_stargateRouter);

        (address _sToken, , , ) = stargateStaking.poolInfo(_stakingPid);
        if (_sToken != address(_lpToken)) revert DifferentAssets();

        sToken = ISToken(_sToken);

        _lpToken.approve(address(stargateStaking), type(uint256).max);
        _underlying.approve(_stargateRouter, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        return sToken.amountLPtoLD(_totalLP());
    }

    /**
     * @notice Returns the total amount of lpToken
     * @dev This function is optional. Some farms might require the user to deposit lpTokens directly into the farm
     */
    function _totalLP() internal view override returns (uint256) {
        (uint256 stake, ) = stargateStaking.userInfo(stakingPid, address(this));
        return stake;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        stargateRouter.addLiquidity(sToken.poolId(), amount, address(this));
        _depositLP(lpToken.balanceOf(address(this)));
    }

    /**
     * @notice Deposits the lpToken directly into the farm
     * @dev This function is optional. Some farms might require the user to deposit lpTokens directly into the farm
     **/
    function _depositLP(uint256 amount) internal override {
        stargateStaking.deposit(stakingPid, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        uint256 lpAmount = amount * sToken.convertRate();
        _withdrawLP(lpAmount);
        IStargateRouter(stargateRouter).instantRedeemLocal(
            sToken.poolId(),
            lpAmount,
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

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claimRewards() internal override {
        try stargateStaking.deposit(stakingPid, 0) {} catch {}
    }
}
