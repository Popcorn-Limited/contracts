// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import "forge-std/Console.sol";
import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../utils/mocks/MockERC20.sol";
import {IVaultController, DeploymentArgs} from "../../src/interfaces/vault/IVaultController.sol";
import {VaultController, IAdapter, VaultInitParams, VaultMetadata} from "../../src/vault/VaultController.sol";
import {VaultFees, IERC4626, IERC20} from "../../src/interfaces/vault/IVault.sol";


contract DebugVaultControllerTest is Test {
    IERC20 public asset = IERC20(address(0));
    IERC4626 public adapter = IERC4626(0x4EC671E19730DD92Aa7cB3399970DBE988F88111);
    address public feeRecipient = 0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E;

    MockERC20 rewardToken;
    string metadataCid = "cid";
    address[8] swapTokenAddresses;
    bytes32 templateId = "MockAdapter";

    IVaultController public controller;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 17542478);
        controller = IVaultController(0x7D51BABA56C2CA79e15eEc9ECc4E92d9c0a7dbeb);

        vm.label(address(controller), "vaultController");
        vm.label(address(controller.adminProxy()), "adminProxy");
        vm.label(address(controller.templateRegistry()), "templateRegistry");
        vm.label(address(controller.deploymentController()), "deploymentController");
        vm.label(address(controller.deploymentController().cloneFactory()), "cloneFactory");
    }


    /*//////////////////////////////////////////////////////////////
                        VAULT DEPLOYMENT
    //////////////////////////////////////////////////////////////*/
    function test__deployVault() public {
        address vaultClone = controller.deployVault(
            VaultInitParams({
                asset: asset,
                adapter: IERC4626(address(0)),
                fees: VaultFees({
                    deposit: 100,
                    withdrawal: 200,
                    management: 300,
                    performance: 400
                }),
                feeRecipient: feeRecipient,
                depositLimit: type(uint256).max,
                owner: address(this)
            }),
            DeploymentArgs({id: templateId, data: abi.encode(uint256(100))}),
            DeploymentArgs({id: "MockStrategy", data: ""}),
            true,
            abi.encode(
                address(rewardToken),
                0.1 ether,
                1 ether,
                true,
                10000000,
                2 days,
                1 days
            ),
            VaultMetadata({
                vault: address(0),
                staking: address(0),
                creator: address(this),
                metadataCID: metadataCid,
                swapTokenAddresses: swapTokenAddresses,
                swapAddress: address(0x5555),
                exchange: uint256(1)
            }),
            0
        );
    }
}
