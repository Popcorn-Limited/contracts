// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../BaseStrategy.sol";
import {IBeefyVault, IBeefyStrat} from "./IBeefy.sol";

/**
 * @title   Beefy Adapter
 * @author  RedVeil
 * @notice  ERC4626 wrapper for Beefy Vaults.
 */
contract BeefyDepositor is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IBeefyVault public beefyVault;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoDeposit_ Controls if `protocolDeposit` gets called on deposit
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function initialize(address asset_, address owner_, bool autoDeposit_, bytes memory strategyInitData_)
        external
        initializer
    {
        address _beefyVault = abi.decode(strategyInitData_, (address));

        beefyVault = IBeefyVault(_beefyVault);

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(asset_).approve(_beefyVault, type(uint256).max);

        _name = string.concat("VaultCraft Beefy ", IERC20Metadata(asset_).name(), " Adapter");
        _symbol = string.concat("vcB-", IERC20Metadata(asset_).symbol());
    }

    function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _name;
    }

    function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function _totalAssets() internal view override returns (uint256) {
        return beefyVault.balanceOf(address(this)).mulDiv(
            beefyVault.balance(), beefyVault.totalSupply(), Math.Rounding.Floor
        );
    }

    /// @notice The amount of beefy shares to withdraw given an amount of adapter shares
    function convertToUnderlyingShares(uint256, uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : shares.mulDiv(beefyVault.balanceOf(address(this)), supply, Math.Rounding.Ceil);
    }

    /// @notice `previewWithdraw` that takes beefy withdrawal fees into account
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        IBeefyStrat strat = IBeefyStrat(beefyVault.strategy());

        uint256 beefyFee;
        try strat.withdrawalFee() returns (uint256 _beefyFee) {
            beefyFee = _beefyFee;
        } catch {
            beefyFee = strat.withdrawFee();
        }

        if (beefyFee > 0) {
            assets = assets.mulDiv(BPS_DENOMINATOR, BPS_DENOMINATOR - beefyFee, Math.Rounding.Floor);
        }

        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    /// @notice `previewRedeem` that takes beefy withdrawal fees into account
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 assets = _convertToAssets(shares, Math.Rounding.Floor);

        IBeefyStrat strat = IBeefyStrat(beefyVault.strategy());

        uint256 beefyFee;
        try strat.withdrawalFee() returns (uint256 _beefyFee) {
            beefyFee = _beefyFee;
        } catch {
            beefyFee = strat.withdrawFee();
        }

        if (beefyFee > 0) {
            assets = assets.mulDiv(BPS_DENOMINATOR - beefyFee, BPS_DENOMINATOR, Math.Rounding.Floor);
        }

        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 assets, uint256, bytes memory) internal override {
        beefyVault.deposit(assets);
    }

    function _protocolWithdraw(uint256, uint256 shares, bytes memory) internal override {
        uint256 beefyShares = convertToUnderlyingShares(0, shares);

        beefyVault.withdraw(beefyShares);
    }
}
