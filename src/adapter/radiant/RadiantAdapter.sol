// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {IRToken, ILendingPool, IProtocolDataProvider, IIncentivesController} from "./IRadiant.sol";
import {IERC20, BaseAdapter, AdapterConfig} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract RadiantAdapter is BaseAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice The Radiant rToken contract
    IRToken public rToken;

    /// @notice The Radiant LendingPool contract
    /// @dev Lending Pool on Arbitrum
    ILendingPool public constant lendingPool = ILendingPool(0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1);

    /// @notice The Radiant Incentives Controller contract
    IIncentivesController public constant controller = IIncentivesController(0xebC85d44cefb1293707b11f707bd3CEc34B4D5fA);

    error LpTokenNotSupported();
    error DifferentAssets(address asset, address underlying);

    function __RadiantAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();
        __BaseAdapter_init(_adapterConfig);

        address radiantDataProvider = abi.decode(
            _adapterConfig.protocolData,
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
        lendingPool.deposit(address(underlying), amount, address(this), 0);
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
        lendingPool.withdraw(address(underlying), amount, address(this));
    }

    function _withdrawLP(uint) internal pure override {
        revert("NO");
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
