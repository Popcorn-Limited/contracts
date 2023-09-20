// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IEllipsis, ILpStaking, IAddressProvider} from "../IEllipsis.sol";
import {IPermissionRegistry} from "../../../../../interfaces/vault/IPermissionRegistry.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract EllipsisPoolAdapter is BaseAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    //address public lpToken;
    address public ellipsisPool;
    address public addressProvider;
    address public ellipsisLPStaking;

    error LpTokenNotSupported();
    error NotEndorsed(address _ellipsisPool);

    function __EllipsisPoolAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();

        __BaseAdapter_init(_adapterConfig);

        (
            address _ellipsisPool,
            address _addressProvider,
            address _ellipsisLPStaking
        ) = abi.decode(
                _protocolConfig.protocolInitData,
                (address, address, address)
            );

        if (
            !IPermissionRegistry(_protocolConfig.registry).endorsed(
                _ellipsisPool
            )
        ) revert NotEndorsed(_ellipsisPool);
        if (
            !IPermissionRegistry(_protocolConfig.registry).endorsed(
                _addressProvider
            )
        ) revert NotEndorsed(_addressProvider);
        if (
            !IPermissionRegistry(_protocolConfig.registry).endorsed(
                _ellipsisLPStaking
            )
        ) revert NotEndorsed(_ellipsisLPStaking);

        ellipsisPool = _ellipsisPool;
        addressProvider = _addressProvider;
        ellipsisLPStaking = _ellipsisLPStaking;
        lpToken = IERC20(
            IAddressProvider(_addressProvider).get_lp_token(_ellipsisPool)
        );

        _adapterConfig.lpToken.approve(
            address(_ellipsisLPStaking),
            type(uint256).max
        );
        _adapterConfig.underlying.approve(
            address(_ellipsisPool),
            type(uint256).max
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        uint256 lpBalance = ILpStaking(ellipsisLPStaking)
            .userInfo(address(lpToken), address(this))
            .depositAmount;

        if (lpBalance > 0) {
            uint256 n_coins = IAddressProvider(addressProvider).get_n_coins(
                ellipsisPool
            );

            address[4] memory coins = IAddressProvider(addressProvider)
                .get_coins(ellipsisPool);
            for (uint256 i = 0; i < n_coins; i++) {
                if (coins[i] == address(underlying)) {
                    return
                        IEllipsis(ellipsisPool).calc_withdraw_one_coin(
                            lpBalance,
                            int128(uint128(i))
                        );
                }
            }
        }
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        underlying.safeTransferFrom(caller, address(this), amount);
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        if (address(ellipsisLPStaking) != address(0)) {
            uint256 n_coins = IAddressProvider(addressProvider).get_n_coins(
                ellipsisPool
            );
            address[4] memory coins = IAddressProvider(addressProvider)
                .get_coins(ellipsisPool);
            if (n_coins == 2) {
                uint256[2] memory amounts;
                for (uint i = 0; i < n_coins; i++) {
                    if (coins[i] == address(underlying)) {
                        amounts[i] = amount;
                    }
                }
                IEllipsis(ellipsisPool).add_liquidity(amounts, 0);
            } else if (n_coins == 3) {
                uint256[3] memory amounts;
                for (uint i = 0; i < n_coins; i++) {
                    if (coins[i] == address(underlying)) {
                        amounts[i] = amount;
                    } else {
                        amounts[i] = 0;
                    }
                }
                IEllipsis(ellipsisPool).add_liquidity(amounts, 0);
            } else {
                uint256[4] memory amounts;
                for (uint i = 0; i < n_coins; i++) {
                    if (coins[i] == address(underlying)) {
                        amounts[i] = amount;
                    }
                }
                IEllipsis(ellipsisPool).add_liquidity(amounts, 0);
            }

            ILpStaking(ellipsisLPStaking).deposit(
                address(lpToken),
                IERC20(lpToken).balanceOf(address(this)),
                false
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 amount, address receiver) internal override {
        if (!paused()) _withdrawUnderlying(amount);
        underlying.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        uint256 _lpShare = convertToUnderlyingShares(0, amount);
        ILpStaking(ellipsisLPStaking).withdraw(
            address(lpToken),
            _lpShare,
            false
        );
        uint256 n_coins = IAddressProvider(addressProvider).get_n_coins(
            ellipsisPool
        );

        uint256 lpTokenBalance = IERC20(lpToken).balanceOf(address(this));

        address[4] memory coins = IAddressProvider(addressProvider).get_coins(
            ellipsisPool
        );
        for (uint256 i = 0; i < n_coins; i++) {
            if (coins[i] == address(underlying)) {
                IEllipsis(ellipsisPool).remove_liquidity_one_coin(
                    lpTokenBalance,
                    int128(uint128(i)),
                    0
                );
                break;
            }
        }
    }

    function convertToUnderlyingShares(
        uint256,
        uint256 shares
    ) public view returns (uint256) {
        uint256 lpBalance = ILpStaking(ellipsisLPStaking)
            .userInfo(address(lpToken), address(this))
            .depositAmount;

        uint256 supply = _totalUnderlying();
        return
            supply == 0
                ? shares
                : shares.mulDiv(lpBalance, supply, Math.Rounding.Up);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = ILpStaking(ellipsisLPStaking).rewardToken();
        try
            ILpStaking(ellipsisLPStaking).claim(address(this), _rewardTokens)
        {} catch {}
    }
}
