// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import "forge-std/Console.sol";
import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "../utils/mocks/MockERC20.sol";
import { AdminProxy } from "../../src/vault/AdminProxy.sol";
import { VaultFactory } from "../../src/vault/VaultFactory.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { VaultRegistry } from "../../src/vault/VaultRegistry.sol";
import { MockStrategyV2 } from "../utils/mocks/MockStrategyV2.sol";
import { BaseVaultConfig, VaultFees} from "./v2/base/BaseVaultTest.sol";
import { IAdminProxy } from "../../src/interfaces/vault/IAdminProxy.sol";
import { IVaultFactory } from "../../src/interfaces/vault/IVaultFactory.sol";
import { IERC20, IVault } from "../../src/vault/v2/base/interfaces/IVault.sol";
import { IVaultRegistry } from "../../src/interfaces/vault/IVaultRegistry.sol";
import { TemplateRegistry, Template } from "../../src/vault/TemplateRegistry.sol";
import { ITemplateRegistry } from "../../src/interfaces/vault/ITemplateRegistry.sol";
import { SingleStrategyVault } from "../../src/vault/v2/vaults/SingleStrategyVault.sol";
import { AdapterConfig, ProtocolConfig } from "../../src/vault/v2/base/interfaces/IBaseAdapter.sol";

contract VaultControllerTest is Test {

    bytes32 public constant VERSION = "v2.0.0";

    bytes32 public constant REBALANCING_VAULT = "RebalancingVault";
    bytes32 public constant SINGLE_STRATEGY_VAULT = "SingleStrategyVault";

    bytes32 public constant LEVERAGE_STRATEGY = "LeverageStrategy";
    bytes32 public constant DEPOSITOR_STRATEGY = "DepositorStrategy";
    bytes32 public constant COMPOUNDER_STRATEGY = "CompounderStrategy";
    bytes32 public constant REWARD_CLAIMER_STRATEGY = "RewardClaimerStrategy";

    IERC20[] public rewardTokens;
    IAdminProxy public adminProxy;
    VaultFactory public vaultFactory;
    IVaultRegistry public vaultRegistry;
    ITemplateRegistry public templateRegistry;

    address public bob = address(0xDCBA);
    address public alice = address(0xABCD);
    address public feeRecipient = address(0x9999);
    address public registry = makeAddr("registry");
    address public notOwner = makeAddr("non owner");
    MockERC20 public asset = new MockERC20("Test Token", "TKN", 18);

    function setUp() public {

        adminProxy = IAdminProxy(address(new AdminProxy(address(this))));

        templateRegistry = ITemplateRegistry(
            address(new TemplateRegistry(address(this)))
        );

        //add strategy template to registry
        address strategy = _createStrategy();
        templateRegistry.addTemplate(
            VERSION,
            DEPOSITOR_STRATEGY,
            strategy
        );

        //add vault template to registry
        address vault = _createVault();
        templateRegistry.addTemplate(
            VERSION,
            SINGLE_STRATEGY_VAULT,
            vault
        );

        vaultFactory = new VaultFactory(
            address(this),
            IVaultRegistry(address(0)),
            templateRegistry
        );

        vaultRegistry = IVaultRegistry(
            address(new VaultRegistry(address(vaultFactory)))
        );

        vaultFactory.setVaultRegistry(address(vaultRegistry));
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

    function testFail__deployVault_With_Vault_Category_Not_Set() public {
        BaseVaultConfig memory vaultConfig = _getVaultConfig();
        address vaultAddress = vaultFactory.deployVault(
            vaultConfig,
            REBALANCING_VAULT,
            DEPOSITOR_STRATEGY
        );
    }

    function testFail__deployVault_With_Strategy_Category_Not_Set() public {
        BaseVaultConfig memory vaultConfig = _getVaultConfig();
        address vaultAddress = vaultFactory.deployVault(
            vaultConfig,
            SINGLE_STRATEGY_VAULT,
            LEVERAGE_STRATEGY
        );
    }

    function test__deployVault() public {
        BaseVaultConfig memory vaultConfig = _getVaultConfig();
        address vaultAddress = vaultFactory.deployVault(
            vaultConfig,
            SINGLE_STRATEGY_VAULT,
            DEPOSITOR_STRATEGY
        );

        IVault vault = IVault(vaultAddress);
        assertEq(vault.name(), vaultConfig.name);
        assertEq(vault.asset(), address(asset));
        assertEq(vault.feeRecipient(), feeRecipient);
        assertEq(vault.fees().deposit, vaultConfig.fees.deposit);
        assertEq(vault.fees().management, vaultConfig.fees.management);
        assertEq(vault.fees().withdrawal, vaultConfig.fees.withdrawal);
        assertEq(vault.fees().performance, vaultConfig.fees.performance);
        assertEq(address(vault.strategy()), templateRegistry.getTemplate(VERSION, DEPOSITOR_STRATEGY));
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
            registry: address (0),
            protocolInitData: abi.encode()
        });

        address adapterAddress = Clones.clone(adapterImplementation);
        MockStrategyV2(adapterAddress).__MockAdapter_init(adapterConfig, protocolConfig);
        return adapterAddress;
    }

    function _createVault() internal returns (address) {
        return address(new SingleStrategyVault());
    }

    function _getVaultConfig() internal returns(BaseVaultConfig memory) {
        return BaseVaultConfig ({
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
