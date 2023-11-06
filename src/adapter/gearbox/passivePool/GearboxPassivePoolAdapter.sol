// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IPoolService, IContractRegistry, IAddressProvider} from "../IGearbox.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../../base/BaseAdapter.sol";

contract GearboxPassivePoolAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The Pool Service Contract
    IPoolService public poolService;

    /// @notice The Diesel Token Contract
    IERC20 public dieselToken;

    error WrongPool();
    error LpTokenNotSupported();

    function __BeefyAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();

        __BaseAdapter_init(_adapterConfig);
        (uint256 _pid, address addressProvider) = abi.decode(
            _adapterConfig.protocolData,
            (uint256, address)
        );

        poolService = IPoolService(
            IContractRegistry(
                IAddressProvider(addressProvider).getContractsRegister()
            ).pools(_pid)
        );
        dieselToken = IERC20(poolService.dieselToken());

        if (address(underlying) != poolService.underlyingToken())
            revert WrongPool();
        _adapterConfig.underlying.approve(
            address(poolService),
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
        uint256 _totalDieselTokens = dieselToken.balanceOf(address(this));

        // roundUp to account for fromDiesel() ReoundDown
        return
            _totalDieselTokens == 0
                ? 0
                : poolService.fromDiesel(_totalDieselTokens);
    }

    function _totalLP() internal pure override returns (uint) {
        revert("NO");
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
        poolService.addLiquidity(amount, address(this), 0);
    }

    function _depositLP(uint) internal pure override {
        revert("NO");
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
        poolService.removeLiquidity(
            poolService.toDiesel(amount) + 1 + 1,
            address(this)
        );
    }

    function _withdrawLP(uint) internal pure override {
        revert("NO");
    }

    function _claim() internal override {}
}
