// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {Test} from "forge-std/Test.sol";
import {CloneFactory} from "../../src/vault/CloneFactory.sol";
import {Template} from "../../src/interfaces/vault/ITemplateRegistry.sol";
import {ClonableWithInitData} from "../utils/mocks/ClonableWithInitData.sol";
import {ClonableWithoutInitData} from "../utils/mocks/ClonableWithoutInitData.sol";

contract CloneFactoryTest is Test {
    CloneFactory factory;
    ClonableWithInitData clonableWithInitDataImpl = new ClonableWithInitData();
    ClonableWithoutInitData clonableWithoutInitDataImpl =
        new ClonableWithoutInitData();

    address nonOwner = makeAddr("non owner");
    address registry = makeAddr("registry");

    string constant metadataCid =
        "QmbWqxBEKC3P8tqsKc98xmWNzrzDtRLMiMPL8wBuTGsMnR";
    bytes4[8] requiredSigs;

    event Deployment(address indexed clone);

    function setUp() public {
        factory = new CloneFactory(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                              DEPLOY
    //////////////////////////////////////////////////////////////*/

    function test__deploy() public {
        Template memory template = Template({
            implementation: address(clonableWithoutInitDataImpl),
            endorsed: false,
            metadataCid: metadataCid,
            requiresInitData: true,
            registry: registry,
            requiredSigs: requiredSigs
        });

        vm.expectEmit(true, false, false, false);
        emit Deployment(address(0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2));

        address clone = factory.deploy(
            template,
            abi.encodeWithSelector(bytes4(keccak256("initialize()")), "")
        );
        assertTrue(ClonableWithoutInitData(clone).initDone());
        assertEq(ClonableWithoutInitData(clone).val(), 10);

        clone = factory.deploy(
            template,
            abi.encodeWithSelector(bytes4(keccak256("initialize()")), "")
        );
        assertTrue(ClonableWithoutInitData(clone).initDone());
    }

    function test__deployWithInitData() public {
        Template memory template = Template({
            implementation: address(clonableWithInitDataImpl),
            endorsed: false,
            metadataCid: metadataCid,
            requiresInitData: true,
            registry: registry,
            requiredSigs: requiredSigs
        });

        bytes memory initData = abi.encodeCall(
            ClonableWithInitData.initialize,
            (100)
        );

        vm.expectEmit(true, false, false, false);
        emit Deployment(address(0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2));

        address clone = factory.deploy(template, initData);

        assertEq(ClonableWithInitData(clone).val(), 100);

        clone = factory.deploy(
            template,
            abi.encodeCall(ClonableWithInitData.initialize, (200))
        );

        assertEq(ClonableWithInitData(clone).val(), 200);
    }

    function test__deploy_nonOwner_failed() public {
        Template memory template = Template({
            implementation: address(clonableWithoutInitDataImpl),
            endorsed: false,
            metadataCid: metadataCid,
            requiresInitData: false,
            registry: registry,
            requiredSigs: requiredSigs
        });

        vm.prank(nonOwner);
        vm.expectRevert("Only the contract owner may perform this action");
        factory.deploy(template, "");
    }

    function test__deploy_init_failed() public {
        Template memory template = Template({
            implementation: address(clonableWithoutInitDataImpl),
            endorsed: false,
            metadataCid: metadataCid,
            requiresInitData: true,
            registry: registry,
            requiredSigs: requiredSigs
        });

        // Call revert method on clone
        bytes memory initData = abi.encodeCall(
            ClonableWithoutInitData.fail,
            ()
        );

        vm.expectRevert(CloneFactory.DeploymentInitFailed.selector);
        factory.deploy(template, initData);
    }
}
