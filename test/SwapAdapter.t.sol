// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {Test} from "forge-std/Test.sol";
import {VaultController, IAdapter, VaultInitParams, VaultMetadata, IERC4626, IERC20, VaultFees, IVault} from "../src/vault/VaultController.sol";
import {IVaultController, DeploymentArgs} from "../src/interfaces/vault/IVaultController.sol";

contract SwapAdapterTest is Test {
    VaultController controller =
        VaultController(0xa199409F99bDBD998Ae1ef4FdaA58b356370837d);
    address[] vaults;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);
    }

    function test_swap() public {
        vaults.push(0xc1D4a319dD7C44e332Bd54c724433C6067FeDd0D);

        emit log_uint(
            IERC4626(0xc1D4a319dD7C44e332Bd54c724433C6067FeDd0D).totalAssets()
        );
        emit log_uint(
            IERC4626(0xc1D4a319dD7C44e332Bd54c724433C6067FeDd0D).totalSupply()
        );
        emit log_named_uint("time", block.timestamp);
        emit log_named_uint(
            "b",
            IVault(0xc1D4a319dD7C44e332Bd54c724433C6067FeDd0D)
                .proposedAdapterTime() +
                IVault(0xc1D4a319dD7C44e332Bd54c724433C6067FeDd0D)
                    .quitPeriod()
        );
        vm.prank(0x22f5413C075Ccd56D575A54763831C4c27A37Bdb);
        controller.changeVaultAdapters(vaults);

        emit log_uint(
            IERC4626(0xc1D4a319dD7C44e332Bd54c724433C6067FeDd0D).totalAssets()
        );
        emit log_uint(
            IERC4626(0xc1D4a319dD7C44e332Bd54c724433C6067FeDd0D).totalSupply()
        );
    }
}
