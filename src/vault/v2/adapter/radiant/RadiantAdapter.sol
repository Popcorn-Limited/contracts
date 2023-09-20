// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {IRToken, ILendingPool, IRewardMinter, IRadiantMining, IProtocolDataProvider, IIncentivesController, IMiddleFeeDistributor} from "./IRadiant.sol";
import {IERC20, BaseAdapter, AdapterConfig, ProtocolConfig} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract RadiantAdapter is BaseAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice The Radiant rToken contract
    IRToken public rToken;

    /// @notice Check to see if Radiant liquidity mining is active
    bool public isActiveMining;

    /// @notice The Radiant LendingPool contract
    ILendingPool public lendingPool;

    /// @notice The Radiant Incentives Controller contract
    IIncentivesController public controller;

    /// @notice Fee managing contract for Radiant rewards
    IMiddleFeeDistributor public middleFee;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant halfRAY = RAY / 2;

    error LpTokenNotSupported();
    error DifferentAssets(address asset, address underlying);

    function __RadiantAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();
        __BaseAdapter_init(_adapterConfig);

        address radiantDataProvider = abi.decode(
            _protocolConfig.protocolInitData,
            (address)
        );

        (address _rToken, , ) = IProtocolDataProvider(radiantDataProvider)
            .getReserveTokensAddresses(address(underlying));

        rToken = IRToken(_rToken);
        if (rToken.UNDERLYING_ASSET_ADDRESS() != address(underlying))
            revert DifferentAssets(
                rToken.UNDERLYING_ASSET_ADDRESS(),
                address(underlying)
            );

        lendingPool = ILendingPool(rToken.POOL());
        controller = IIncentivesController(rToken.getIncentivesController());
        IRewardMinter minter = IRewardMinter(controller.rewardMinter());

        _adapterConfig.underlying.approve(
            address(lendingPool),
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
        return rToken.balanceOf(address(this));
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
        lendingPool.deposit(address(underlying), amount, address(this), 0);
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
        lendingPool.withdraw(address(underlying), amount, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        if (address(controller) == address(0)) return;

        try controller.claimAll(address(this)) {} catch {}
    }
}
