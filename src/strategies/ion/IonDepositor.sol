// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

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
        address _ionPool = abi.decode(strategyInitData_, (address));

        if (IIonPool(_ionPool).underlying() != asset_) revert DifferentAssets();

        ionPool = IIonPool(_ionPool);

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(asset_).approve(_ionPool, type(uint256).max);

        _name = string.concat("VaultCraft IonDepositor ", IERC20Metadata(asset_).name(), " Adapter");
        _symbol = string.concat("vc-ion-", IERC20Metadata(asset_).symbol());
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
        return ionPool.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into aave lending pool
    function _protocolDeposit(uint256 assets, uint256, bytes memory) internal virtual override {
        ionPool.supply(address(this), assets, _proof);
    }

    /// @notice Withdraw from lending pool
    function _protocolWithdraw(uint256 assets, uint256, bytes memory) internal virtual override {
        ionPool.withdraw(address(this), assets);
    }

    /*//////////////////////////////////////////////////////////////
                          MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    function setProof(bytes32[] calldata newProof) external onlyOwner {
        _proof = newProof;
    }
}
