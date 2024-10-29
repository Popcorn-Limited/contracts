// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

import {ControllerModule, ModuleCall, ISafe, Enum} from "src/peripheral/gnosis/controllerModule/MainControllerModule.sol";
import {OracleVault, IPriceOracle} from "src/vaults/multisig/phase1/OracleVault.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "src/utils/Owned.sol";
import {OwnerManager} from "safe-smart-account/base/OwnerManager.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {TakeOverSafeLib} from "src/peripheral/gnosis/controllerModule/TakeOverSafeLib.sol";
import {OracleVaultController, Limit} from "src/peripheral/OracleVaultController.sol";


contract DrawdownModule is Owned {
    using FixedPointMathLib for uint256;

    OracleVault public vault;
    ControllerModule public controller;
    ISafe public safe;
    ModuleCall[] public tokenBalanceCalls;

    constructor(
        address vault_,
        address controller_,
        address owner_,
        address[] memory newOwners_,
        uint256 newThreshold_,
        uint256 liquidationBonus_
    ) Owned(owner_) {
        vault = OracleVault(vault_);
        controller = ControllerModule(controller_);
        safe = ISafe(ControllerModule(controller_).gnosisSafe());

        newOwners = newOwners_;
        newThreshold = newThreshold_;
        liquidationBonus = liquidationBonus_;
    }

    /*//////////////////////////////////////////////////////////////
                        EXECUTION LOGIC
    //////////////////////////////////////////////////////////////*/

    function liquidateSafe(ModuleCall[] memory calls) external {
        IPriceOracle oracle = vault.oracle();
        address asset = address(vault.asset());
        uint256 shareValue = oracle.getQuote(
            10 ** vault.decimals(),
            address(vault),
            asset
        );

        OracleVaultController oracleController = OracleVaultController(
            Owned(address(oracle)).owner()
        );
        uint256 hwm = oracleController.highWaterMarks(address(vault));
        (uint256 jump, uint256 drawdown) = oracleController.limits(
            address(vault)
        );

        if (shareValue >= hwm.mulDivDown(1e18 - drawdown, 1e18))
            revert("Drawdown acceptable");

        // Execute calls to liquidate all positions in the safe to the vault asset
        controller.executeModuleTransactions(calls);

        // Make sure there is no leftover token in the safe besides the vault asset
        // A malicious liquidator might want to keep leftover tokens in the safe to make the appearance that the safe holds less than totalAssets to enable a liquidation
        for (uint256 i; i < tokenBalanceCalls.length; i++) {
            (bool success, bytes memory data) = tokenBalanceCalls[i].to.call(
                tokenBalanceCalls[i].data
            );
            if (!success) revert("Token balance call failed");

            // TODO add an acceptable dust value instead of 0
            if (abi.decode(data, (uint256)) > 0) revert("Leftover token");
        }

        // Transfer funds into this module
        uint256 assetBalance = ERC20(asset).balanceOf(controller.gnosisSafe());
        ModuleCall[] memory calls = new ModuleCall[](1);
        calls[0] = ModuleCall({
            to: asset,
            value: 0,
            data: abi.encodeWithSelector(
                ERC20.transfer.selector,
                assetBalance,
                address(this)
            ),
            operation: Enum.Operation.Call
        });
        controller.executeModuleTransactions(calls);

        // Pay out liquidation bounty
        uint256 bounty = assetBalance.mulDivDown(1e18 - liquidationBonus, 1e18);
        ERC20(asset).transfer(msg.sender, bounty);

        // Transfer remaining assets back to the safe
        ERC20(asset).transfer(address(safe), assetBalance - bounty);

        // Put DAO in control of the safe
        TakeOverSafeLib.takeoverSafe(
            address(controller),
            newOwners,
            newThreshold
        );
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    address[] public newOwners;
    uint256 public newThreshold;
    uint256 public liquidationBonus;

    function setNewOwners(address[] memory newOwners_) external onlyOwner {
        newOwners = newOwners_;
    }

    function setNewThreshold(uint256 newThreshold_) external onlyOwner {
        if (newThreshold_ < 1) revert("Invalid threshold");

        newThreshold = newThreshold_;
    }

    function setLiquidationBonus(uint256 liquidationBonus_) external onlyOwner {
        if (liquidationBonus_ >= 1e18) revert("Invalid bonus");
        liquidationBonus = liquidationBonus_;
    }
}
