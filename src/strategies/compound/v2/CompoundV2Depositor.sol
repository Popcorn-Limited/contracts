// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../../BaseStrategy.sol";
import {ICToken, IComptroller} from "./ICompoundV2.sol";
import {LibCompound} from "./LibCompound.sol";

/**
 * @title   CompoundV2 Adapter
 * @author  RedVeil
 * @notice  ERC4626 wrapper for CompoundV2 Vaults.
 */
contract CompoundV2Depositor is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The Compound cToken contract
    ICToken public cToken;

    /// @notice The Compound Comptroller contract
    IComptroller public comptroller;

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
    function initialize(
        address asset_,
        address owner_,
        bool autoDeposit_,
        bytes memory strategyInitData_
    ) external initializer {
        (address cToken_, address comptroller_) = abi.decode(
            strategyInitData_,
            (address, address)
        );

        cToken = ICToken(cToken_);
        comptroller = IComptroller(comptroller_);

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(asset_).approve(cToken_, type(uint256).max);

        _name = string.concat(
            "VaultCraft CompoundV2 ",
            IERC20Metadata(asset_).name(),
            " Adapter"
        );
        _symbol = string.concat("vcCv2-", IERC20Metadata(asset_).symbol());
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
        return LibCompound.viewUnderlyingBalanceOf(cToken, address(this));
    }

    function convertToUnderlyingShares(
        uint256,
        uint256 shares
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    cToken.balanceOf(address(this)),
                    supply,
                    Math.Rounding.Ceil
                );
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into aave lending pool
    function _protocolDeposit(
        uint256 assets,
        uint256,
        bytes memory
    ) internal override {
        cToken.mint(assets);
    }

    /// @notice Withdraw from lending pool
    function _protocolWithdraw(uint256, uint256 shares) internal override {
        cToken.redeem(convertToUnderlyingShares(0, shares));
    }
}