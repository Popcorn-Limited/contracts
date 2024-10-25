// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

import {ControllerModule, ModuleCall} from "src/peripheral/gnosis/controllerModule/MainControllerModule.sol";
import {MultisigVault} from "src/vaults/multisig/phase1/MultisigVault.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "src/utils/Owned.sol";

contract DrawdownModule is Owned {
    MultisigVault public vault;
    ControllerModule public controller;
    ModuleCall[] public tokenBalanceCalls;

    address[] public newOwners;
    uint256 public newThreshold;

    constructor(
        address vault_,
        address controller_,
        address owner_
    ) Owned(owner_) {
        vault = MultisigVault(vault_);
        controller = ControllerModule(controller_);
    }

    function liquidateSafe(ModuleCall[] memory calls) external {
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

        address asset = vault.asset();
        uint256 assetBalance = ERC20(asset).balanceOf(controller.gnosisSafe());
        uint256 totalAssets = vault.totalAssets();
        // TODO add a drawdown parameter
        if (assetBalance < totalAssets) {
            // Transfer funds into this module
            ModuleCall[] memory calls = new ModuleCall[](1);
            calls[0] = ModuleCall({
                to: asset,
                value: 0,
                data: abi.encodeWithSelector(
                    ERC20.transfer.selector,
                    assetBalance,
                    address(this)
                ),
                operation: Operation.Call
            });
            controller.executeModuleTransactions(calls);

            // Pay out liquidation bounty
            uint256 bounty = assetBalance.mulDivDown(100, 10_000);
            ERC20(asset).transfer(msg.sender, bounty);

            // Transfer remaining asset to vault
            ERC20(asset).transfer(address(vault), assetBalance - bounty);

            // Put DAO in control of the safe
            _takeoverSafe();
        }
    }

    function _takeoverSafe(
        address[] memory newOwners,
        uint256 newThreshold
    ) internal {
        address _gnosisSafe = gnosisSafe;
        ISafe safe = ISafe(_gnosisSafe);
        address[] memory owners = safe.getOwners();

        // remove owners
        for (uint256 i = (owners.length - 1); i > 0; --i) {
            bool success = safe.execTransactionFromModule({
                to: _gnosisSafe,
                value: 0,
                data: abi.encodeCall(
                    IOwnerManager.removeOwner,
                    (owners[i - 1], owners[i], 1)
                ),
                operation: Operation.Call
            });
            if (!success) {
                revert("SM: owner removal failed");
            }
        }

        for (uint256 i = 0; i < newOwners.length; i++) {
            bool success;
            if (i == 0) {
                if (newOwners[i] == owners[i]) continue;
                success = safe.execTransactionFromModule({
                    to: _gnosisSafe,
                    value: 0,
                    data: abi.encodeCall(
                        IOwnerManager.swapOwner,
                        (SENTINEL_OWNERS, owners[i], newOwners[i])
                    ),
                    operation: Operation.Call
                });
                if (!success) {
                    revert("SM: owner replacement failed");
                }
                continue;
            }
            success = safe.execTransactionFromModule({
                to: _gnosisSafe,
                value: 0,
                data: abi.encodeCall(
                    IOwnerManager.addOwnerWithThreshold,
                    (newOwners[i], 1)
                ),
                operation: Operation.Call
            });
            if (!success) {
                revert("SM: owner addition failed");
            }
        }

        if (newThreshold > 1) {
            bool success = safe.execTransactionFromModule({
                to: _gnosisSafe,
                value: 0,
                data: abi.encodeCall(
                    IOwnerManager.changeThreshold,
                    (newThreshold)
                ),
                operation: Operation.Call
            });
            if (!success) {
                revert("SM: change threshold failed");
            }
        }
    }

    function setTokenBalanceCalls(
        ModuleCall[] memory calls
    ) external onlyOwner {
        for (uint256 i; i < calls.length; i++) {
            if (calls[i].to == address(0)) revert("Invalid call");
            if (calls[i].data.length == 0) revert("Invalid call data");
            if (calls[i].value != 0) revert("Invalid call value");
            if (calls[i].operation != Operation.Call)
                revert("Invalid call operation");

            // We want to get the balance of all tokens in the safe that are not the vault asset
            if (calls[i].to == vault.asset()) revert("Invalid call");

            delete tokenBalanceCalls;

            tokenBalanceCalls.push(calls[i]);
        }
    }

    function setNewOwners(address[] memory newOwners_) external onlyOwner {
        newOwners = newOwners_;
    }

    function setNewThreshold(uint256 newThreshold_) external onlyOwner {
        newThreshold = newThreshold_;
    }
}
