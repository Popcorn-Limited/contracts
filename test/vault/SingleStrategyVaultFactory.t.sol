// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "../utils/mocks/MockERC20.sol";
import { SingleStrategyVaultFactory } from "../../src/vault/SingleStrategyVaultFactory.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { VaultRegistry } from "../../src/vault/VaultRegistry.sol";
import { MockStrategyV2 } from "../utils/mocks/MockStrategyV2.sol";
import { BaseVaultConfig, VaultFees} from "./v2/base/BaseVaultTest.sol";
import { IERC20, IVault } from "../../src/vault/v2/base/interfaces/IVault.sol";
import { IVaultRegistry } from "../../src/interfaces/vault/IVaultRegistry.sol";
import { TemplateRegistry } from "../../src/vault/TemplateRegistry.sol";
import { ITemplateRegistry } from "../../src/interfaces/vault/ITemplateRegistry.sol";
import { SingleStrategyVault } from "../../src/vault/v2/vaults/SingleStrategyVault.sol";
import { AdapterConfig, ProtocolConfig } from "../../src/vault/v2/base/interfaces/IBaseAdapter.sol";

contract SingleStrategyVaultFactoryTest is Test {

    bytes32 public constant VERSION = "v2.0.0";

    IERC20[] public rewardTokens;
    SingleStrategyVaultFactory public vaultFactory;
    IVaultRegistry public vaultRegistry;
    IVaultRegistry public customStrategyVaultRegistry;
    ITemplateRegistry public templateRegistry;

    address strategy;
    address public bob = address(0xDCBA);
    address public feeRecipient = address(0x9999);

    MockERC20 public asset = new MockERC20("Test Token", "TKN", 18);

    function setUp() public {
        templateRegistry = ITemplateRegistry(address(new TemplateRegistry(address(this))));

        //add strategy template to registry
        strategy = _createStrategy();
        templateRegistry.addTemplate(
            VERSION,
            "STRATEGY",
            strategy
        );

        address vaultImpl = address(new SingleStrategyVault());


        vaultRegistry = IVaultRegistry(address(
            new VaultRegistry(address(this))
        ));
        customStrategyVaultRegistry = IVaultRegistry(address(
            new VaultRegistry(address(this))
        ));
        vaultFactory = new SingleStrategyVaultFactory(
            address(this),
            vaultRegistry,
            customStrategyVaultRegistry,
            templateRegistry,
            vaultImpl
        );
        vaultRegistry.addFactory(address(vaultFactory));
        customStrategyVaultRegistry.addFactory(address(vaultFactory));
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public {
        assertEq(vaultFactory.owner(), address(this));
        assertEq(address(vaultFactory.vaultRegistry()), address(vaultRegistry));
        assertEq(address(vaultFactory.templateRegistry()), address(templateRegistry));
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function test__deployVault() public {
        BaseVaultConfig memory vaultConfig = _getVaultConfig();
        address vaultAddress = vaultFactory.deployVault(
            vaultConfig,
            strategy
        );

        IVault vault = IVault(vaultAddress);
        assertEq(vault.name(), vaultConfig.name);
        assertEq(vault.asset(), address(asset));
        assertEq(vault.feeRecipient(), feeRecipient);
        assertEq(vault.fees().deposit, vaultConfig.fees.deposit);
        assertEq(vault.fees().management, vaultConfig.fees.management);
        assertEq(vault.fees().withdrawal, vaultConfig.fees.withdrawal);
        assertEq(vault.fees().performance, vaultConfig.fees.performance);

        assertTrue(vaultRegistry.vaults(vaultAddress));
    }

    function test__cannotDeployVaultWithUnknownStrategy() public {
        BaseVaultConfig memory vaultConfig = _getVaultConfig();
        vm.expectRevert(SingleStrategyVaultFactory.InvalidStrategy.selector);
        address vaultAddress = vaultFactory.deployVault(
            vaultConfig,
            vm.addr(3) 
        );
    }

    function test__deployCustomStrategyVault() public {
        BaseVaultConfig memory vaultConfig = _getVaultConfig();
        address strat = _createStrategy();
        address vaultAddress = vaultFactory.deployCustomStrategyVault(
            vaultConfig,
            strat
        );

        IVault vault = IVault(vaultAddress);
        assertEq(vault.name(), vaultConfig.name);
        assertEq(vault.asset(), address(asset));
        assertEq(vault.feeRecipient(), feeRecipient);
        assertEq(vault.fees().deposit, vaultConfig.fees.deposit);
        assertEq(vault.fees().management, vaultConfig.fees.management);
        assertEq(vault.fees().withdrawal, vaultConfig.fees.withdrawal);
        assertEq(vault.fees().performance, vaultConfig.fees.performance);

        assertTrue(customStrategyVaultRegistry.vaults(vaultAddress));
    }

    function test__canMigrateVaultToMainRegistry() public {
        BaseVaultConfig memory vaultConfig = _getVaultConfig();
        address strat = _createStrategy();
        address vaultAddress = vaultFactory.deployCustomStrategyVault(
            vaultConfig,
            strat
        );
        assertTrue(customStrategyVaultRegistry.vaults(vaultAddress));
    
        templateRegistry.addTemplate(VERSION, "STRATEGY", strat);

        vaultFactory.migrateVault(vaultAddress);

        assertTrue(vaultRegistry.vaults(vaultAddress));
    }

    function test__cannotMigrateVaultWithUnknownStrategey() public {
        BaseVaultConfig memory vaultConfig = _getVaultConfig();
        address strat = _createStrategy();
        address vaultAddress = vaultFactory.deployCustomStrategyVault(
            vaultConfig,
            strat
        );
        assertTrue(customStrategyVaultRegistry.vaults(vaultAddress));
    
        vm.expectRevert(SingleStrategyVaultFactory.InvalidStrategy.selector);
        vaultFactory.migrateVault(vaultAddress);
    }

    function test__cannotMigrateUnknownVault() public {
        vm.expectRevert(SingleStrategyVaultFactory.NotAVault.selector);
        vaultFactory.migrateVault(address(2));
    }

    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/
    function _createStrategy() internal returns (address) {
        address adapterImplementation = address(new MockStrategyV2());

        AdapterConfig memory adapterConfig = AdapterConfig({
            underlying: IERC20(address(asset)),
            lpToken: IERC20(address(0)),
            useLpToken: false,
            rewardTokens: rewardTokens,
            owner: address(this)
        });

        ProtocolConfig memory protocolConfig = ProtocolConfig({
            registry: address(0),
            protocolInitData: ""
        });

        address adapterAddress = Clones.clone(adapterImplementation);
        MockStrategyV2(adapterAddress).__MockAdapter_init(adapterConfig, protocolConfig);
        return adapterAddress;
    }

    function _getVaultConfig() internal view returns(BaseVaultConfig memory) {
        return BaseVaultConfig({
            asset_: IERC20(address(asset)),
            fees: VaultFees({
                deposit: 100,
                withdrawal: 0,
                management: 100,
                performance: 100
            }),
            feeRecipient: feeRecipient,
            depositLimit: 1000,
            owner: bob,
            protocolOwner: bob,
            name: "VaultCraft SingleStrategyVault"
        });
    }
}