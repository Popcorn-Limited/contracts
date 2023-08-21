// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {IDotDotStaking} from "./IDotDot.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../base/BaseAdapter.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";


contract DotDotAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    IDotDotStaking public lpStaking;

    error InvalidToken();

    function __DotDotAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        __BaseAdapter_init(_adapterConfig);

        lpStaking = IDotDotStaking(_protocolConfig.registry);

        if (lpStaking.depositTokens(address (underlying)) == address(0))
            revert InvalidToken();

        _adapterConfig.lpToken.approve(address(lpStaking), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalAssets() internal view override returns (uint256) {
        return lpStaking.userBalances(address(this), address (underlying));
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
        lpStaking.deposit(address(this), address (underlying), amount);
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
        lpStaking.withdraw(address(this), address(underlying), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        address[] memory tokens = new address[](1);
        tokens[0] = address (underlying);
        try lpStaking.claim(address(this), tokens, 0) {
        } catch {}
    }
}
