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
        vaults.push(0x5d344226578DC100b2001DA251A4b154df58194f);

        emit log_uint(
            IERC4626(0x5d344226578DC100b2001DA251A4b154df58194f).totalAssets()
        );
        emit log_uint(
            IERC4626(0x5d344226578DC100b2001DA251A4b154df58194f).totalSupply()
        );
        emit log_named_uint("time", block.timestamp);
        emit log_named_uint(
            "b",
            IVault(0x5d344226578DC100b2001DA251A4b154df58194f)
                .proposedAdapterTime() +
                IVault(0x5d344226578DC100b2001DA251A4b154df58194f)
                    .quitPeriod()
        );
        vm.prank(0x22f5413C075Ccd56D575A54763831C4c27A37Bdb);
        controller.changeVaultAdapters(vaults);

        emit log_uint(
            IERC4626(0x5d344226578DC100b2001DA251A4b154df58194f).totalAssets()
        );
        emit log_uint(
            IERC4626(0x5d344226578DC100b2001DA251A4b154df58194f).totalSupply()
        );
    }
}
