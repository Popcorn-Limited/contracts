//// SPDX-License-Identifier: GPL-3.0
//// Docgen-SOLC: 0.8.15
//pragma solidity ^0.8.15;
//
//import {Script} from "forge-std/Script.sol";
//import {CloneRegistry} from "../src/vault/CloneRegistry.sol";
//import {CloneFactory} from "../src/vault/CloneFactory.sol";
//import {PermissionRegistry} from "../src/vault/PermissionRegistry.sol";
//import {TemplateRegistry, Template} from "../src/vault/TemplateRegistry.sol";
//import {DeploymentController} from "../src/vault/DeploymentController.sol";
//import {VaultFactory, IAdapter, VaultInitParams, VaultMetadata, IERC4626, IERC20, VaultFees} from "../src/vault/VaultFactory.sol";
//import {Vault} from "../src/vault/Vault.sol";
//import {AdminProxy} from "../src/vault/AdminProxy.sol";
//import {VaultRegistry} from "../src/vault/VaultRegistry.sol";
//
//import {MultiRewardEscrow} from "../src/utils/MultiRewardEscrow.sol";
//import {MultiRewardStaking} from "../src/utils/MultiRewardStaking.sol";
//
//import {ICloneRegistry} from "../src/interfaces/vault/ICloneRegistry.sol";
//import {ICloneFactory} from "../src/interfaces/vault/ICloneFactory.sol";
//import {IPermissionRegistry, Permission} from "../src/interfaces/vault/IPermissionRegistry.sol";
//import {ITemplateRegistry} from "../src/interfaces/vault/ITemplateRegistry.sol";
//import {IDeploymentController} from "../src/interfaces/vault/IDeploymentController.sol";
//import {IVaultRegistry} from "../src/interfaces/vault/IVaultRegistry.sol";
//import {IAdminProxy} from "../src/interfaces/vault/IAdminProxy.sol";
//import {IVaultFactory, DeploymentArgs} from "../src/interfaces/vault/IVaultFactory.sol";
//
//import {IMultiRewardEscrow} from "../src/interfaces/IMultiRewardEscrow.sol";
//import {IMultiRewardStaking} from "../src/interfaces/IMultiRewardStaking.sol";
//import {IOwned} from "../src/interfaces/IOwned.sol";
//import {IPausable} from "../src/interfaces/IPausable.sol";
//
//import {VaultRouter} from "../src/vault/VaultRouter.sol";
//import {YearnAdapter} from "../src/vault/adapter/yearn/YearnAdapter.sol";
//import {BeefyAdapter} from "../src/vault/adapter/beefy/BeefyAdapter.sol";
//
//import {VaultRouter} from "../src/vault/VaultRouter.sol";
//
//import {MockStrategy} from "../test/utils/mocks/MockStrategy.sol";
//
//contract DeployVaultSystem is Script {
//    ITemplateRegistry templateRegistry =
//        ITemplateRegistry(0x1Ea65ae3d7E60E374221cdE29844df81F447D68c);
//    IPermissionRegistry permissionRegistry =
//        IPermissionRegistry(0xB67C4c9C3CebCeC2FD3fDE436340D728D990A8d9);
//    ICloneRegistry cloneRegistry =
//        ICloneRegistry(0x57c041e4504b05A7B3A3597134a1DA78e719fc73);
//    IVaultRegistry vaultRegistry =
//        IVaultRegistry(0xB205e94D402742B919E851892f7d515592a7A6cC);
//
//    ICloneFactory factory =
//        ICloneFactory(0x99fDFcC95a45ca4604E3c1eB86f2b5d9E217f460);
//    IDeploymentController deploymentController =
//        IDeploymentController(0xa8C5815f6Ea5F7A1551541B0d7F970D546126bDB);
//    IAdminProxy adminProxy =
//        IAdminProxy(0xcC09F5bd7582D02Bb31825d09589F4773B65eCc9);
//
//    IMultiRewardStaking staking;
//    IMultiRewardEscrow escrow =
//        IMultiRewardEscrow(0x23DBbE898A8b69eA0681F8d8C74f4B17dAAe5FCd);
//
//    VaultFactory controller =
//        VaultFactory(0xa199409F99bDBD998Ae1ef4FdaA58b356370837d);
//    VaultRouter router;
//
//    IERC20 pop = IERC20(0x6F0fecBC276de8fC69257065fE47C5a03d986394);
//
//    address stakingImpl = 0x0b64206eAdD25f27145D1B29A27e3a242d0922F9;
//    address yearnImpl = 0x1DB17afE14732A5267a0839D5f3dE0AF1426cb9E;
//    address beefyImpl = 0x69c5290Eeae87d10D0b8d8dC6291DD31292A6A41;
//    address compV2Impl = 0x55A768Bf8D5fcD42E82cb08C81D02A48FB84c6be;
//    address strategyImpl;
//    address vaultImpl = 0x3602C76ab5ADA70d40A8e09BcfB91F2c195E20BE;
//
//    address deployer;
//    address feeRecipient = address(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);
//
//    bytes32 templateCategory = "templateCategory";
//    bytes32 templateId = "MockAdapter";
//    string metadataCid = "";
//    bytes4[8] requiredSigs;
//    address[8] swapTokenAddresses;
//
//    event log(string);
//    event log_uint(uint256);
//    event log_address(address);
//
//    event log_named_address(string str, address addr);
//
//    function run() public {
//        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//        deployer = vm.addr(deployerPrivateKey);
//
//        emit log_address(deployer);
//
//        vm.startBroadcast(deployerPrivateKey);
//
//        // stakingImpl = address(new MultiRewardStaking());
//        // yearnImpl = address(new YearnAdapter());
//        // beefyImpl = address(new BeefyAdapter());
//        // strategyImpl = address(new MockStrategy());
//        // vaultImpl = address(new Vault());
//
//        // adminProxy = IAdminProxy(address(new AdminProxy(deployer)));
//
//        // permissionRegistry = IPermissionRegistry(
//        //     address(new PermissionRegistry(address(adminProxy)))
//        // );
//        // vaultRegistry = IVaultRegistry(
//        //     address(new VaultRegistry(address(adminProxy)))
//        // );
//        // escrow = IMultiRewardEscrow(
//        //     address(new MultiRewardEscrow(address(adminProxy), feeRecipient))
//        // );
//        // router = new VaultRouter(vaultRegistry);
//
//        // deployDeploymentController();
//        // deploymentController.nominateNewOwner(address(adminProxy));
//        // adminProxy.execute(
//        //     address(deploymentController),
//        //     abi.encodeWithSelector(IOwned.acceptOwnership.selector, "")
//        // );
//
//        // controller = new VaultController(
//        //     deployer,
//        //     adminProxy,
//        //     deploymentController,
//        //     vaultRegistry,
//        //     permissionRegistry,
//        //     escrow
//        // );
//
//        // adminProxy.nominateNewOwner(address(controller));
//        // controller.acceptAdminProxyOwnership();
//
//        // bytes32[] memory templateCategories = new bytes32[](4);
//        // templateCategories[0] = "Vault";
//        // templateCategories[1] = "Adapter";
//        // templateCategories[2] = "Strategy";
//        // templateCategories[3] = "Staking";
//        // controller.addTemplateCategories(templateCategories);
//
//        // addTemplate(
//        //     "Staking",
//        //     "MultiRewardStaking",
//        //     stakingImpl,
//        //     address(0),
//        //     true,
//        //     true
//        // );
//        // addTemplate(
//        //     "Adapter",
//        //     "YearnAdapter",
//        //     yearnImpl,
//        //     address(0x3199437193625DCcD6F9C9e98BDf93582200Eb1f),
//        //     true,
//        //     true
//        // );
//        // addTemplate(
//        //     "Adapter",
//        //     "BeefyAdapter",
//        //     beefyImpl,
//        //     address(permissionRegistry),
//        //     true,
//        //     true
//        // );
//        addTemplate(
//            "Adapter",
//            "CompoundV2Adapter",
//            compV2Impl,
//            address(0x95Af143a021DF745bc78e845b54591C53a8B3A51),
//            true,
//            true
//        );
//        // addTemplate("Vault", "V1", vaultImpl, address(0), true, true);
//
//        // emit log("!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
//        // emit log_named_address("VaultController: ", address(controller));
//        // emit log_named_address("VaultRegistry: ", address(vaultRegistry));
//        // emit log_named_address("VaultRouter: ", address(router));
//        // emit log("!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
//
//        // // approve pop for staking rewards
//        // pop.approve(address(controller), 2000 ether);
//
//        // // approve usdc for inital deposit
//        // IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).approve(
//        //     address(controller),
//        //     100e6
//        // );
//
//        // // deploy usdc yearn vault
//        // address yearn = controller.deployVault(
//        //     VaultInitParams({
//        //         asset: IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
//        //         adapter: IERC4626(address(0)),
//        //         fees: VaultFees({
//        //             deposit: 0,
//        //             withdrawal: 0,
//        //             management: 0,
//        //             performance: 0
//        //         }),
//        //         feeRecipient: feeRecipient,
//        //         depositLimit: type(uint256).max,
//        //         owner: deployer
//        //     }),
//        //     DeploymentArgs({id: "YearnAdapter", data: abi.encode(uint256(1))}),
//        //     DeploymentArgs({id: "", data: ""}),
//        //     false,
//        //     "",
//        //     VaultMetadata({
//        //         vault: address(0),
//        //         staking: address(0),
//        //         creator: address(this),
//        //         metadataCID: metadataCid,
//        //         swapTokenAddresses: swapTokenAddresses,
//        //         swapAddress: address(0),
//        //         exchange: uint256(0)
//        //     }),
//        //     0
//        // );
//
//        // emit log_named_address("YearnVault: ", yearn);
//
//        // // approve and stake vault
//        // VaultMetadata memory yearnMetadata = vaultRegistry.getVault(yearn);
//        // IERC20(yearn).approve(yearnMetadata.staking, 100e15);
//        // IMultiRewardStaking(yearnMetadata.staking).deposit(100e15, deployer);
//
//        // // deposit usdc and stake through the router
//        // IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).approve(
//        //     address(router),
//        //     100e6
//        // );
//        // router.depositAndStake(IERC4626(yearn), 100e6, deployer);
//
//        // IERC20(yearnMetadata.staking).approve(address(router), 10e15);
//        // router.redeemAndWithdraw(IERC4626(yearn), 10e15, deployer, deployer);
//
//        // // beefyVault stEth/eth = 0xa7739fd3d12ac7F16D8329AF3Ee407e19De10D8D
//        // setPermission(0xD019FD6267F93ebE5A92DEBB760135a4F02a75F7, true, false);
//        // // beefyBooster = 0xAe3F0C61F3Dc48767ccCeF3aD50b29437BE4b1a4
//        // setPermission(0xAe3F0C61F3Dc48767ccCeF3aD50b29437BE4b1a4, true, false);
//
//        // // approve stEth/eth for inital deposit
//        // IERC20(0x06325440D014e39736583c165C2963BA99fAf14E).approve(
//        //     address(controller),
//        //     10e18
//        // );
//
//        // // crvSthEth/Eth = 0x06325440D014e39736583c165C2963BA99fAf14E
//        // // deploy stEth/eth beefy vault
//        // address beefy = controller.deployVault(
//        //     VaultInitParams({
//        //         asset: IERC20(0xF753A50fc755c6622BBCAa0f59F0522f264F006e),
//        //         adapter: IERC4626(address(0)),
//        //         fees: VaultFees({
//        //             deposit: 0,
//        //             withdrawal: 0,
//        //             management: 0,
//        //             performance: 0
//        //         }),
//        //         feeRecipient: feeRecipient,
//        //         depositLimit: type(uint256).max,
//        //         owner: deployer
//        //     }),
//        //     DeploymentArgs({
//        //         id: "BeefyAdapter",
//        //         data: abi.encode(
//        //             0xD019FD6267F93ebE5A92DEBB760135a4F02a75F7,
//        //             address(0)
//        //         )
//        //     }),
//        //     DeploymentArgs({id: "", data: ""}),
//        //     false,
//        //     "",
//        //     VaultMetadata({
//        //         vault: address(0),
//        //         staking: address(0),
//        //         creator: deployer,
//        //         metadataCID: "",
//        //         swapTokenAddresses: swapTokenAddresses,
//        //         swapAddress: address(0),
//        //         exchange: uint256(0)
//        //     }),
//        //     0
//        // );
//
//        // emit log_named_address("BeefyVault: ", beefy);
//
//        // // approve and stake vault
//        // VaultMetadata memory beefyMetadata = vaultRegistry.getVault(beefy);
//        // IERC20(beefy).approve(beefyMetadata.staking, 10e27);
//        // IMultiRewardStaking(beefyMetadata.staking).deposit(10e27, deployer);
//
//        vm.stopBroadcast();
//    }
//
//    function deployDeploymentController() public {
//        factory = ICloneFactory(address(new CloneFactory(deployer)));
//        cloneRegistry = ICloneRegistry(address(new CloneRegistry(deployer)));
//        templateRegistry = ITemplateRegistry(
//            address(new TemplateRegistry(deployer))
//        );
//
//        deploymentController = IDeploymentController(
//            address(
//                new DeploymentController(
//                    deployer,
//                    factory,
//                    cloneRegistry,
//                    templateRegistry
//                )
//            )
//        );
//
//        factory.nominateNewOwner(address(deploymentController));
//        cloneRegistry.nominateNewOwner(address(deploymentController));
//        templateRegistry.nominateNewOwner(address(deploymentController));
//        deploymentController.acceptDependencyOwnership();
//    }
//
//    function addTemplate(
//        bytes32 templateCategory,
//        bytes32 templateId,
//        address implementation,
//        address registry,
//        bool requiresInitData,
//        bool endorse
//    ) public {
//        // deploymentController.addTemplate(
//        //     templateCategory,
//        //     templateId,
//        //     Template({
//        //         implementation: implementation,
//        //         endorsed: false,
//        //         metadataCid: metadataCid,
//        //         requiresInitData: requiresInitData,
//        //         registry: registry,
//        //         requiredSigs: requiredSigs
//        //     })
//        // );
//        bytes32[] memory templateCategories = new bytes32[](1);
//        bytes32[] memory templateIds = new bytes32[](1);
//        templateCategories[0] = templateCategory;
//        templateIds[0] = templateId;
//        if (endorse)
//            controller.toggleTemplateEndorsements(
//                templateCategories,
//                templateIds
//            );
//    }
//
//    function setPermission(
//        address target,
//        bool endorsed,
//        bool rejected
//    ) public {
//        address[] memory targets = new address[](1);
//        Permission[] memory permissions = new Permission[](1);
//        targets[0] = target;
//        permissions[0] = Permission(endorsed, rejected);
//        controller.setPermissions(targets, permissions);
//    }
//}
