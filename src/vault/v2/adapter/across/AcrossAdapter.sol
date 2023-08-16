// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../base/BaseAdapter.sol";
import {IAcrossHop, IAcceleratingDistributor} from "./IAcross.sol";


contract AcrossAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The Across Hop contract
    address public acrossHop;

    /// @notice The Across token distributor contract
    address public acrossDistributor;

    /// @notice The Across lp token contract
    address public lpToken;

    error Disabled();
    error NotEndorsed(address _acrossHop);

    function __AcrossAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        __BaseAdapter_init(_adapterConfig);

        (address _acrossHop, address _acrossDistributor) = abi.decode(
            acrossInitData,
            (address, address)
        );

        if (!IPermissionRegistry(registry).endorsed(_acrossHop))
            revert NotEndorsed(_acrossHop);
        if (!IPermissionRegistry(registry).endorsed(_acrossDistributor))
            revert NotEndorsed(_acrossDistributor);

        if (!IAcrossHop(_acrossHop).pooledTokens(asset()).isEnabled)
            revert Disabled();
        acrossHop = _acrossHop;
        acrossDistributor = _acrossDistributor;

        lpToken = IAcrossHop(acrossHop).pooledTokens(asset()).lpToken;

        _adapterConfig.underlying.approve(address(_acrossHop), type(uint256).max);
        _adapterConfig.lpToken.approve(address(_acrossDistributor), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                             ACCOUNTING LOGIC
     //////////////////////////////////////////////////////////////*/

    function _totalAssets() internal view override returns (uint256) {
        uint256 totalLpBalance = IAcceleratingDistributor(acrossDistributor)
        .getUserStake(lpToken, address(this))
        .cumulativeBalance;
        return (totalLpBalance * _exchangeRateCurrent()) / 1e18;
    }

    function _exchangeRateCurrent() internal view returns (uint256) {
        IAcrossHop.PooledToken memory pooledToken = IAcrossHop(acrossHop)
        .pooledTokens(asset());
        uint256 lpTokenTotalSupply = IERC20(pooledToken.lpToken).totalSupply();
        if (lpTokenTotalSupply == 0) return 1e18; // initial rate is 1:1 between LP tokens and collateral.

        // First, update fee counters and local accounting of finalized transfers from L2 -> L1.

        uint256 accumulatedFees = _getAccumulatedFees(
            pooledToken.undistributedLpFees,
            pooledToken.lastLpFeeUpdate
        );
        pooledToken.undistributedLpFees -= accumulatedFees;
        pooledToken.lastLpFeeUpdate = uint32(
            IAcrossHop(acrossHop).getCurrentTime()
        );

        // Check if the l1Token balance of the contract is greater than the liquidReserves. If it is then the bridging
        // action from L2 -> L1 has concluded and the local accounting can be updated.
        // Note: this calculation must take into account the bond when it's acting on the bond token and there's an
        // active request.
        uint256 balance = IERC20(asset()).balanceOf(acrossHop);
        uint256 balanceSansBond = asset() ==
        address(IAcrossHop(acrossHop).bondToken()) &&
        _activeRequest()
            ? balance - IAcrossHop(acrossHop).bondAmount()
            : balance;
        if (balanceSansBond > pooledToken.liquidReserves) {
            // Note the numerical operation below can send utilizedReserves to negative. This can occur when tokens are
            // dropped onto the contract, exceeding the liquidReserves.
            pooledToken.utilizedReserves -= int256(
                balanceSansBond - pooledToken.liquidReserves
            );
            pooledToken.liquidReserves = balanceSansBond;
        }

        // ExchangeRate := (liquidReserves + utilizedReserves - undistributedLpFees) / lpTokenSupply
        // Both utilizedReserves and undistributedLpFees contain assigned LP fees. UndistributedLpFees is gradually
        // decreased over the smear duration using _updateAccumulatedLpFees. This means that the exchange rate will
        // gradually increase over time as undistributedLpFees goes to zero.
        // utilizedReserves can be negative. If this is the case, then liquidReserves is offset by an equal
        // and opposite size. LiquidReserves + utilizedReserves will always be larger than undistributedLpFees so this
        // int will always be positive so there is no risk in underflow in type casting in the return line.
        int256 numerator = int256(pooledToken.liquidReserves) +
        pooledToken.utilizedReserves -
        int256(pooledToken.undistributedLpFees);
        return (uint256(numerator) * 1e18) / lpTokenTotalSupply;
    }

    function _activeRequest() internal view returns (bool) {
        return
        IAcrossHop(acrossHop)
        .rootBundleProposal()
        .unclaimedPoolRebalanceLeafCount != 0;
    }

    // Calculate the unallocated accumulatedFees from the last time the contract was called.
    function _getAccumulatedFees(
        uint256 undistributedLpFees,
        uint256 lastLpFeeUpdate
    ) internal view returns (uint256) {
        // accumulatedFees := min(undistributedLpFees * lpFeeRatePerSecond * timeFromLastInteraction, undistributedLpFees)
        // The min acts to pay out all fees in the case the equation returns more than the remaining fees.
        uint256 timeFromLastInteraction = IAcrossHop(acrossHop)
        .getCurrentTime() - lastLpFeeUpdate;
        uint256 maxUndistributedLpFees = (undistributedLpFees *
        IAcrossHop(acrossHop).lpFeeRatePerSecond() *
            timeFromLastInteraction) / (1e18);
        return
            maxUndistributedLpFees < undistributedLpFees
                ? maxUndistributedLpFees
                : undistributedLpFees;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount) internal override {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        IAcrossHop(acrossHop).addLiquidity(asset(), amount);
        _depositLP(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositLP(uint256 amount) internal override {
        uint256 balance = lpToken.balanceOf(address(this));
        IAcceleratingDistributor(acrossDistributor).stake(lpToken, balance);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 amount) internal override {
        _withdrawUnderlying(amount);
        underlying.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overridden. Some farms require the user to into an lpToken before depositing
     *      others might use the underlying directly
     **/
    function _withdrawLP(uint256 amount) internal override {
        uint256 _lpShare = convertToUnderlyingShares(0, amount);
        IAcceleratingDistributor(acrossDistributor).unstake(lpToken, _lpShare);
        IAcrossHop(acrossHop).removeLiquidity(asset(), _lpShare, false);
    }

    /// @notice The amount of beefy shares to withdraw given an amount of adapter shares
    function convertToUnderlyingShares(
        uint256,
        uint256 shares
    ) public view override returns (uint256) {
        uint256 totalLpBalance = IAcceleratingDistributor(acrossDistributor)
        .getUserStake(lpToken, address(this))
        .cumulativeBalance;

        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(totalLpBalance, supply, Math.Rounding.Up);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        try
        IAcceleratingDistributor(acrossDistributor).withdrawReward(lpToken)
        {
            success = true;
        } catch {}
    }
}
