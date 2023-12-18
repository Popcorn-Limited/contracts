import {CREATE3Script} from "./base/CREATE3Script.sol";

import {AdminProxy} from "../src/AdminProxy.sol";
import {SingleStrategyVaultFactory} from "../src/SingleStrategyVaultFactory.sol";
import {VaultRegistry} from "../src/VaultRegistry.sol";
import {TemplateRegistry} from "../src/TemplateRegistry.sol";

contract DeployInfra is CREATE3Script {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run()
        public
        returns (
            AdminProxy adminProxy,
            SingleStrategyVaultFactory vaultFactory,
            VaultRegistry vaultRegistry,
            VaultRegistry customStrategyVaultRegistry,
            TemplateRegistry templateRegistry
        )
    {
        address deployer = vm.envAddress("DEPLOYER");

        vm.startBroadcast(deployer);

        adminProxy = AdminProxy(
            create3.deploy(
                getCreate3ContractSalt("AdminProxy"), bytes.concat(type(AdminProxy).creationCode, abi.encode(deployer))
            )
        );

        vaultRegistry = VaultRegistry(
            create3.deploy(
                getCreate3ContractSalt("VaultRegistry"),
                bytes.concat(
                    type(VaultRegistry).creationCode,
                    // VaultRegistry is owned by admin proxy
                    abi.encode(address(adminProxy))
                )
            )
        );
        adminProxy.execute(
            address(vaultRegistry),
            abi.encodeWithSelector(VaultRegistry.addFactory.selector, getCreate3Contract("SingleStrategyVaultFactory"))
        );

        customStrategyVaultRegistry = VaultRegistry(
            create3.deploy(
                getCreate3ContractSalt("CustomStrategyVaultRegistry"),
                bytes.concat(
                    type(VaultRegistry).creationCode,
                    // VaultRegistry is owned by admin proxy
                    abi.encode(address(adminProxy))
                )
            )
        );
        adminProxy.execute(
            address(customStrategyVaultRegistry),
            abi.encodeWithSelector(VaultRegistry.addFactory.selector, getCreate3Contract("SingleStrategyVaultFactory"))
        );

        templateRegistry = TemplateRegistry(
            create3.deploy(
                getCreate3ContractSalt("TemplateRegistry"),
                bytes.concat(
                    type(TemplateRegistry).creationCode,
                    // TemplateRegistry is owned by AdminProxy
                    abi.encode(address(adminProxy))
                )
            )
        );

        vaultFactory = SingleStrategyVaultFactory(
            create3.deploy(
                getCreate3ContractSalt("SingleStrategyVaultFactory"),
                bytes.concat(
                    type(SingleStrategyVaultFactory).creationCode,
                    abi.encode(address(adminProxy), address(vaultRegistry), address(templateRegistry))
                )
            )
        );

        vm.stopBroadcast();
    }
}
