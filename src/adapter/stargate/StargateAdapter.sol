// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../base/BaseAdapter.sol";
import {ISToken, IStargateStaking, IStargateRouter} from "./IStargate.sol";

contract StargateAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The Stargate LpStaking contract
    IStargateStaking internal constant stargateStaking = IStargateStaking(0xB0D502E938ed5f4df2E681fE6E419ff29631d62b);
    IStargateRouter internal constant stargateRouter = IStargateRouter(0x8731d54E9D02c286767d56ac03e8037C07e01e98);

    uint256 internal stakingPid;
    ISToken internal sToken;

    error StakingIdOutOfBounds();
    error DifferentAssets();

    function __StargateAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        __BaseAdapter_init(_adapterConfig);

        (uint256 _stakingPid) = abi.decode(
            _adapterConfig.protocolData,
            (uint256)
        );

        if (_stakingPid >= stargateStaking.poolLength())
            revert StakingIdOutOfBounds();

        stakingPid = _stakingPid;

        (address _sToken, , , ) = stargateStaking.poolInfo(_stakingPid);
        if (_sToken != address(_adapterConfig.lpToken)) revert DifferentAssets();

        sToken = ISToken(_sToken);

        _adapterConfig.lpToken.approve(address(stargateStaking), type(uint256).max);
        _adapterConfig.underlying.approve(address(stargateRouter), type(uint256).max);
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

    function _deposit(uint256 amount, address caller) internal override {
        if (useLpToken) {
            lpToken.safeTransferFrom(caller, address(this), amount);
            _depositLP(amount);
        } else {
            if (caller != address(this))
            underlying.safeTransferFrom(caller, address(this), amount);
            _depositUnderlying(amount);
        }
    }

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
    function _withdraw(uint256 amount, address receiver) internal override {
        if (useLpToken) {
            if (!paused()) _withdrawLP(amount);
            lpToken.safeTransfer(receiver, amount);
        } else {
            if (!paused()) _withdrawUnderlying(amount);
            underlying.safeTransfer(receiver, amount);
        }
    }

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
    function _claim() internal override {
        try stargateStaking.deposit(stakingPid, 0) {} catch {}
    }
}
