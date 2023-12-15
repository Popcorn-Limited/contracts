// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseAdapter, IERC20, AdapterConfig} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {ILido, VaultAPI, ICurveMetapool, IWETH} from "./ILido.sol";

contract LidoAdapter is BaseAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;

    ICurveMetapool public constant StableSwapSTETH =
        ICurveMetapool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    uint256 public slippage; // 1e18 = 100% slippage, 1e14 = 1 BPS slippage

    // TODO: instead of swapping stETH for ETH and sending that to the user we could also
    // just let them withdraw stETH
    
    // - even if stETH depegs from ETH, the amount of funds the user will receive in that scenario doesn't change.
    //   Whether they get 1 stETH worth 0.8 ETH or just 0.8 ETH directly is the same thing.
    // 
    // But, we reduce gas costs for the strategy since we don't have to execute the expensive Curve swap.
    //
    // If the user wants to receive ETH, we let them do that through the frontend. That way we can handle the slippage
    // better as well.
    // 
    // Another possibility would be to initiate a withdrawal and send the user the ERc721 withdrawal receipt
    // https://docs.lido.fi/guides/lido-tokens-integration-guide/#withdrawals-unsteth
    // Although I think that's the worst solution from a UX standpoint    
    //

    ILido public constant lido = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    // address public immutable weth;
    IWETH public constant weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    error LpTokenNotSupported();

    function __LidoAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();
        __BaseAdapter_init(_adapterConfig);

        (uint256 _slippage) = abi.decode(
            _adapterConfig.protocolData,
            (uint256)
        );

        slippage = _slippage;

        IERC20(address(lido)).approve(
            address(StableSwapSTETH),
            type(uint256).max
        );

        // we send raw ETH to both the Lido stETH and the Curve pool so we don't have to
        // execute any other approvals here
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        uint256 assets = lido.balanceOf(address(this));
        return assets - assets.mulDiv(slippage, 1e18, Math.Rounding.Up);
    }

    function _totalLP() internal pure override returns (uint) {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        if (caller != address(this))
            underlying.safeTransferFrom(caller, address(this), amount);
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        weth.withdraw(amount); // Grab native Eth from Weth contract
        lido.submit{value: amount}(FEE_RECIPIENT); // Submit to Lido Contract
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
        uint256 amountRecieved = StableSwapSTETH.exchange(
            STETHID,
            WETHID,
            convertToUnderlyingShares(amount),
            0
        );
        weth.deposit{value: amountRecieved}(); // get wrapped eth back
    }

    function _withdrawLP(uint) internal pure override {
        revert("NO");
    }

    function convertToUnderlyingShares(
        uint256 shares
    ) public view returns (uint256) {
        uint256 supply = _totalUnderlying();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    lido.balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
    }

    receive() external payable {}

    function _claim() internal pure override {}
}
