// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "../../../utils/mocks/MockERC20.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { MockStrategyV2 } from "../../../utils/mocks/MockStrategyV2.sol";
import { IVault } from "../../../../src/vault/v2/base/interfaces/IVault.sol";
import { BaseVaultConfig, BaseVault, VaultFees } from "../../../../src/vault/v2/base/BaseVault.sol";
import {
    IERC4626Upgradeable as IERC4626, IERC20Upgradeable as IERC20
} from "openzeppelin-contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {
    AdapterConfig, ProtocolConfig
} from "../../../../src/vault/v2/base/BaseAdapter.sol";


abstract contract BaseVaultTest is Test {

    IVault public vault;
    MockERC20 public asset;
    MockStrategyV2 public adapter;
    address public vaultImplementation;
    address public adapterImplementation;

    address public bob = address(0xDCBA);
    address public alice = address(0xABCD);
    address public feeRecipient = address(0x4444);

    function setUp() public virtual {
        vm.label(feeRecipient, "feeRecipient");
        vm.label(alice, "alice");
        vm.label(bob, "bob");

        asset = new MockERC20("Mock Token", "TKN", 18);

        adapter = _createAdapter();
        vm.label(address(adapter), "adapter");

        vault = _createVault();
        vm.label(address(vault), "vault");

        vault.initialize(
            _getVaultConfig(),
            address(adapter)
        );
    }


    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/
    function _createAdapter() internal virtual returns (MockStrategyV2);

    function _createVault() internal virtual returns (IVault);

    function _getVaultConfig() internal virtual returns(BaseVaultConfig memory);

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function test__metadata() public {
        IVault newVault = _createVault();

        uint256 callTime = block.timestamp;
        newVault.initialize(
            _getVaultConfig(),
            address(adapter)
        );

        assertEq(newVault.name(), _getVaultConfig().name);
        assertEq(newVault.symbol(), "vc-TKN");
        assertEq(newVault.decimals(), 27);

        assertEq(address(newVault.asset()), address(asset));
        assertEq(address(newVault.strategy()), address(adapter));
        assertEq(newVault.owner(), bob);

        VaultFees memory vaultFees = newVault.fees();
        VaultFees memory expectedVaultFees = _getVaultConfig().fees;

        assertEq(vaultFees.deposit, expectedVaultFees.deposit);
        assertEq(vaultFees.withdrawal, expectedVaultFees.withdrawal);
        assertEq(vaultFees.management, expectedVaultFees.management);
        assertEq(vaultFees.performance, expectedVaultFees.performance);
        assertEq(newVault.feeRecipient(), feeRecipient);
        assertEq(newVault.highWaterMark(), 1e9);

        assertEq(newVault.quitPeriod(), 3 days);
        assertEq(asset.allowance(address(newVault), address(adapter)), type(uint256).max);
    }

    function testFail__initialize_strategy_is_addressZero() public {
        IVault vault = _createVault();
        vm.label(address(vault), "vault");

        vault.initialize(
            _getVaultConfig(),
            address(0)
        );
    }


}
