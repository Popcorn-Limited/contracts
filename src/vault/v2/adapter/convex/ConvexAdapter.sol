// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {IConvexBooster, IConvexRewards, IRewards} from "./IConvex.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../base/BaseAdapter.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";


contract ConvexAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The poolId inside Convex booster for relevant Curve lpToken.
    uint256 public pid;

    /// @notice The booster address for Convex
    IConvexBooster public convexBooster;

    /// @notice The Convex convexRewards.
    IConvexRewards public convexRewards;

    error AssetMismatch();

    function __ConvexAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        __BaseAdapter_init(_adapterConfig);

        uint256 _pid = abi.decode(_protocolConfig.protocolInitData, (uint256));
        convexBooster = IConvexBooster(_protocolConfig.registry);

        (address _asset, , , address _convexRewards, , ) = convexBooster.poolInfo(_pid);
        convexRewards = IConvexRewards(_convexRewards);

        if (_asset != address(underlying)) revert AssetMismatch();

        _adapterConfig.underlying.approve(convexBooster, type(uint256).max);
        pid = _pid;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        return convexRewards.balanceOf(address(this));
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

    function _deposit(uint256 amount) internal override {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        convexBooster.deposit(pid, amount, true);
    }


    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/
    function _withdraw(uint256 amount, address receiver) internal override {
        _withdrawUnderlying(amount);
        underlying.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        convexRewards.withdrawAndUnwrap(amount, false);
    }


    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        try convexRewards.getReward(address(this), true) {
            success = true;
        } catch {}
    }
}
