// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20Metadata, ERC20, IERC20, Math} from "./BaseStrategy.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";

/**
 * @title   BaseStrategy
 * @author  RedVeil
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 *
 * The ERC4626 compliant base contract for all adapter contracts.
 * It allows interacting with an underlying protocol.
 * All specific interactions for the underlying protocol need to be overriden in the actual implementation.
 * The adapter can be initialized with a strategy that can perform additional operations. (Leverage, Compounding, etc.)
 */
abstract contract Converter is BaseStrategy {
    using Math for uint256;

    address public yieldAsset;
    address[] internal tokens;

    IPriceOracle public oracle;

    uint256 public slippage;
    uint256 public floatRatio;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoDeposit_ Controls if `protocolDeposit` gets called on deposit
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function __EnsoConverter_init(
        address asset_,
        address owner_,
        bool autoDeposit_,
        bytes memory strategyInitData_
    ) internal onlyInitializing {
        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        address oracle_;
        (yieldAsset, oracle_, slippage, floatRatio) = abi.decode(
            strategyInitData_,
            (address, address, uint256, uint256)
        );
        oracle = IPriceOracle(oracle_);

        tokens.push(asset_);
        tokens.push(yieldAsset);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.
    function _totalAssets() internal view override returns (uint256) {
        return
            oracle.getQuote(
                IERC20(yieldAsset).balanceOf(address(this)),
                yieldAsset,
                asset()
            );
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice deposit into the underlying protocol.
    function _protocolDeposit(
        uint256 assets,
        uint256 shares,
        bytes memory data
    ) internal override {
        // stay empty
    }

    /// @notice Withdraw from the underlying protocol.
    function _protocolWithdraw(
        uint256 assets,
        uint256 shares,
        bytes memory data
    ) internal override {
        // stay empty
    }

    /*//////////////////////////////////////////////////////////////
                        PUSH/PULL LOGIC
    //////////////////////////////////////////////////////////////*/

    error SlippageTooHigh();
    error NotEnoughFloat();

    function pushFunds(
        uint256 assets,
        bytes memory data
    ) external override onlyKeeperOrOwner {
        // caching
        IERC20 _asset = IERC20(asset());

        uint256 ta = this.totalAssets();
        uint256 bal = _asset.balanceOf(address(this));

        IERC20(yieldAsset).transferFrom(msg.sender, address(this), assets);

        uint256 postTa = this.totalAssets();

        uint256 withdrawable = oracle.getQuote(assets, yieldAsset, asset());

        if (floatRatio > 0) {
            uint256 balAfterFloat = bal.mulDiv(
                10_000 - floatRatio,
                10_000,
                Math.Rounding.Floor
            );
            if (balAfterFloat < withdrawable) withdrawable = balAfterFloat;
        } else {
            if (bal < withdrawable) withdrawable = bal;
        }

        if (
            postTa - withdrawable <
            ta.mulDiv(10_000 - slippage, 10_000, Math.Rounding.Floor)
        ) revert SlippageTooHigh();

        _asset.transfer(msg.sender, withdrawable);
    }

    function pullFunds(
        uint256 assets,
        bytes memory data
    ) external override onlyKeeperOrOwner {
        // caching
        IERC20 _asset = IERC20(asset());

        uint256 ta = this.totalAssets();
        uint256 bal = IERC20(yieldAsset).balanceOf(address(this));

        _asset.transferFrom(msg.sender, address(this), assets);

        uint256 postTa = this.totalAssets();

        uint256 withdrawable = oracle.getQuote(assets, yieldAsset, asset());

        if (
            postTa - withdrawable <
            ta.mulDiv(10_000 - slippage, 10_000, Math.Rounding.Floor)
        ) revert SlippageTooHigh();

        _asset.transfer(msg.sender, withdrawable);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    function setSlippage(uint256 slippage_) external onlyOwner {
        slippage = slippage_;
    }

    function setFloatRatio(uint256 floatRatio_) external onlyOwner {
        floatRatio = floatRatio_;
    }
}
