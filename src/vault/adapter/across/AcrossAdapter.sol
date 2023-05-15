// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {IPermissionRegistry} from "../../../interfaces/vault/IPermissionRegistry.sol";
import {IAcrossHop, IAcceleratingDistributor} from "./IAcross.sol";

contract AcrossAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    address public acrossHop;
    address public acrossDistributor;
    address public lpToken;

    uint256 public exchangeRate;

    error NotEndorsed(address _acrossHop);
    error Disabled();

    /**
     * @notice Initialize a new Across Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry Endorsement Registry to check if the across adapter is endorsed.
     * @param acrossInitData Encoded data for the across adapter initialization.
     * @dev `_acrossHop` - the address of Across Hop Pool.
     * @dev `_acrossDistributor` - the address of Accelerating Distributor.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory acrossInitData
    ) external initializer {
        (address _acrossHop, address _acrossDistributor) = abi.decode(
            acrossInitData,
            (address, address)
        );
        __AdapterBase_init(adapterInitData);

        if (!IPermissionRegistry(registry).endorsed(_acrossHop))
            revert NotEndorsed(_acrossHop);
        if (!IPermissionRegistry(registry).endorsed(_acrossDistributor))
            revert NotEndorsed(_acrossDistributor);

        _name = string.concat(
            "Popcorn Across ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("popAxc-", IERC20Metadata(asset()).symbol());

        if (!IAcrossHop(_acrossHop).pooledTokens(asset()).isEnabled)
            revert Disabled();
        acrossHop = _acrossHop;
        acrossDistributor = _acrossDistributor;

        lpToken = IAcrossHop(acrossHop).pooledTokens(asset()).lpToken;

        IERC20(lpToken).approve(acrossDistributor, type(uint256).max);
        IERC20(asset()).approve(_acrossHop, type(uint256).max);
    }

    function name()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _name;
    }

    function symbol()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _symbol;
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
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        IAcrossHop(acrossHop).addLiquidity(asset(), amount);
        uint256 balance = IERC20(lpToken).balanceOf(address(this));
        IAcceleratingDistributor(acrossDistributor).stake(lpToken, balance);
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

    function _protocolWithdraw(
        uint256,
        uint256 share
    ) internal virtual override {
        uint256 _lpShare = convertToUnderlyingShares(0, share);

        IAcceleratingDistributor(acrossDistributor).unstake(lpToken, _lpShare);
        IAcrossHop(acrossHop).removeLiquidity(asset(), _lpShare, false);
    }

    function claim() public override onlyStrategy returns (bool success) {
        try
            IAcceleratingDistributor(acrossDistributor).withdrawReward(lpToken)
        {
            success = true;
        } catch {}
    }

    /// @notice The token rewarded
    function rewardTokens() external view override returns (address[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = IAcceleratingDistributor(acrossDistributor)
            .rewardToken();
        return _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                      EIP-165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(
        bytes4 interfaceId
    ) public pure override(WithRewards, AdapterBase) returns (bool) {
        return
            interfaceId == type(IWithRewards).interfaceId ||
            interfaceId == type(IAdapter).interfaceId;
    }
}
