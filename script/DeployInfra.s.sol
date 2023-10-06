import {CREATE3Script} from "./base/CREATE3Script.sol";

import {AdminProxy} from "../src/vault/AdminProxy.sol";
import {VaultFactory} from "../src/vault/VaultFactory.sol";
import {VaultRegistry} from "../src/vault/VaultRegistry.sol";
import {TemplateRegistry} from "../src/vault/TemplateRegistry.sol";

contract DeployInfra is CREATE3Script {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() public returns (
        AdminProxy adminProxy,
        VaultFactory vaultFactory,
        VaultRegistry vaultRegistry,
        TemplateRegistry templateRegistry
    ) {
        address deployer = vm.envAddress("DEPLOYER");
    
        vm.startBroadcast(deployer);
    
        adminProxy = AdminProxy(
            create3.deploy(
                getCreate3ContractSalt("AdminProxy"),
                bytes.concat(
                    type(AdminProxy).creationCode,
                    abi.encode(deployer)
                )
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
        adminProxy.execute(target, abi.encodeWithSelector(VaultRegistry.addFactory.selector, getCreate3Contract("VaultFactory")));

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

        vaultFactory = VaultFactory(
            create3.deploy(
                getCreate3ContractSalt("VaultFactory"),
                bytes.concat(
                    type(VaultFactory).creationCode,
                    abi.encode(address(adminProxy), address(vaultRegistry), address(templateRegistry))
                )
            )
        );

        vm.stopBroadcast();
    }
}