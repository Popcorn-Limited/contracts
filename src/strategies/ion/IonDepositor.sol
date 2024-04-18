// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../BaseStrategy.sol";
import {IIonPool} from "./IIonProtocol.sol";

/**
 * @title   Ion Adapter
 * @author  RedVeil
 * @notice  ERC4626 wrapper for Ion Protocol Markets.
 *
 * An ERC4626 compliant Wrapper for ....
 */

contract IonDepositor is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IIonPool public ionPool;

    bytes32[] internal _proof;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    error DifferentAssets();

    /**
     * @notice Initialize a new Ion Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param ionInitData Encoded data for the base adapter initialization.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address,
        bytes memory ionInitData
    ) external initializer {
        __BaseStrategy_init(adapterInitData);

        address _asset = asset();
        address _ionPool = abi.decode(ionInitData, (address));

        if (IIonPool(_ionPool).underlying() != _asset) revert DifferentAssets();

        ionPool = IIonPool(_ionPool);

        _name = string.concat(
            "VaultCraft IonDepositor ",
            IERC20Metadata(_asset).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-ion-", IERC20Metadata(_asset).symbol());

        IERC20(_asset).approve(_ionPool, type(uint256).max);
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
        return ionPool.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into aave lending pool
    function _protocolDeposit(
        uint256 assets,
        uint256
    ) internal virtual override {
        ionPool.supply(address(this), assets, _proof);
    }

    /// @notice Withdraw from lending pool
    function _protocolWithdraw(
        uint256 assets,
        uint256
    ) internal virtual override {
        ionPool.withdraw(address(this), assets);
    }

    /*//////////////////////////////////////////////////////////////
                          MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    function setProof(bytes32[] calldata newProof) external onlyOwner {
        _proof = newProof;
    }
}
