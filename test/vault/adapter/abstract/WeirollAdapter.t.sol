// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {ConvexAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IConvexBooster, IConvexRewards, IWithRewards, IStrategy} from "../../../../src/vault/adapter/convex/ConvexAdapter.sol";
import {ConvexTestConfigStorage, ConvexTestConfig} from "../convex/ConvexTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../utils/mocks/MockStrategyClaimer.sol";
import {WeirollUniversalAdapter, VmCommand} from "../../../../src/vault/adapter/weiroll/WeirollAdapter.sol";
import {WeirollUtils, InputIndex, OutputIndex} from "../../../../src/vault/adapter/weiroll/WeirollUtils.sol";
import {stdJson} from "forge-std/StdJson.sol";

struct Command {
    uint256 commandType; // 0 delegateCall, 1 call, 2 static call, 3 call with value
    string signature;
    address target;
}

contract WeirollAdapterTest is AbstractAdapterTest {
    using Math for uint256;
    using stdJson for string;

    IConvexBooster convexBooster =
        IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IConvexRewards convexRewards;
    address rewardPool = address(0x79579633029a61963eDfbA1C0BE22498b6e0D33D);

    uint256 pid;
    WeirollUniversalAdapter adapterContract;
    WeirollUtils encoder;

    address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    address baseAsset = address(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E); //crvUSD
    address router = address(0xF0d4c12A5768D806021F80a262B4d39d26C58b8D);

    bytes[] claimStates = new bytes[](17);

    string jsonConfig;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 19262400);

        jsonConfig = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/test/vault/adapter/abstract/WeirollAdapterConfig.json" // TODO PATH var
            )
        );

        testConfigStorage = ITestConfigStorage(
            address(new ConvexTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        uint256 _pid = abi.decode(testConfig, (uint256));

        pid = _pid;
        (address _asset, , , , , ) = convexBooster
            .poolInfo(pid);
        // convexRewards = IConvexRewards(_convexRewards);

        setUpBaseTest(
            IERC20(_asset),
            address(new WeirollUniversalAdapter()),
            address(convexBooster),
            10,
            "Convex",
            true
        );
        
        vm.prank(address(this));

        vm.label(address(convexBooster), "convexBooster");
        // vm.label(address(convexRewards), "convexRewards");
        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        encoder = new WeirollUtils();

        // ENCODE TOTAL ASSET 
        bytes32[] memory tComm = new bytes32[](1);
        bytes[] memory tStates = new bytes[](1);

        (tComm, tStates) = _totalAssetsCommand();

        // ---------------------------------------------- 
        // ENCODE DEPOSIT         
        bytes32[] memory depCommands = new bytes32[](1);
        bytes[] memory depStates = new bytes[](2);

        (depCommands, depStates) = _depositCommand();

        // ---------------------------------------------- 
        // ENCODE WITHDRAW 
        bytes32[] memory wCommands = new bytes32[](1);
        bytes[] memory wStates = new bytes[](1);
        (wCommands, wStates) = _withdrawCommand();

        // ---------------------------------------------- 
        // ENCODE HARVEST
        bytes32[] memory claimComms = new bytes32[](11);
        bytes32[] memory claimedComms = new bytes32[](11);

        (claimComms, claimStates) = _harvestCommand();
        _updateStateCommand();

        // ---------------------------------------------- 
        // ENCODE ALL COMMANDS 
        bytes memory commands = abi.encode(depCommands,depStates,wCommands,wStates,tComm,tStates,claimComms,claimStates);

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            commands
        );

        adapterContract = WeirollUniversalAdapter(address(adapter));

        adapter.toggleAutoHarvest();
    }

    /*//////////////////////////////////////////////////////////////
                          GENERAL VIEWS
    //////////////////////////////////////////////////////////////*/

    // TODO
    function test__rewardsTokens() public override {
        address[] memory rewardTokens = IWithRewards(address(adapter))
            .rewardTokens();
        address CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        address CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        assertEq(rewardTokens[0], CRV, "CRV");
        assertEq(rewardTokens[1], CVX, "CVX");
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), address(asset), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Convex ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcCvx-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(convexBooster)),
            type(uint256).max,
            "allowance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                              CLAIM
    //////////////////////////////////////////////////////////////*/

    function test__claim() public override {
        strategy = IStrategy(address(new MockStrategyClaimer()));
        createAdapter();
        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfigStorage.getTestConfig(0)
        );

        _mintAssetAndApproveForAdapter(1000e18, bob);

        vm.prank(bob);
        adapter.deposit(1000e18, bob);

        vm.warp(block.timestamp + 30 days);

        adapter.harvest();

        address[] memory rewardTokens = IWithRewards(address(adapter))
            .rewardTokens();
        assertEq(rewardTokens[0], 0xD533a949740bb3306d119CC777fa900bA034cd52); // CRV
        assertEq(rewardTokens[1], 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B); // CVX

        assertGt(IERC20(rewardTokens[0]).balanceOf(address(adapter)), 0);
        assertGt(IERC20(rewardTokens[1]).balanceOf(address(adapter)), 0);
    }

    function test_protocol_deposit() public {
        deal(address(asset), bob, 100);
        uint256 amount = 10;

        // get data before
        uint256 totAssetsBefore = adapter.totalAssets();
        uint256 bobBalBefore = asset.balanceOf(bob);

        // EXECUTE DEPOSIT        
        vm.startPrank(bob);
        asset.approve(address(adapter), amount);
        adapter.deposit(amount, bob);
        vm.stopPrank();

        // get data after 
        uint256 totAssetsAfter = adapter.totalAssets();
        uint256 bobBalAfter = asset.balanceOf(bob);

        // assertions
        assertEq(totAssetsAfter, totAssetsBefore + amount);
        assertEq(bobBalAfter, bobBalBefore - amount);
    }

    function test_protocol_withdraw() public {
        deal(address(asset), bob, 100);
        uint256 amountDep = 10;
        uint256 amountWith = 8;

        // EXECUTE DEPOSIT        
        vm.startPrank(bob);
        asset.approve(address(adapter), amountDep);
        adapter.deposit(amountDep, bob);
        vm.stopPrank();

        // get data before
        uint256 totAssetsBefore = adapterContract.totalAssets();
        uint256 bobBalBefore = asset.balanceOf(bob);

        // EXECUTE WITHDRAW        
        vm.prank(bob);
        adapter.withdraw(amountWith, bob, bob);

        // get data after 
        uint256 totAssetsAfter = adapterContract.totalAssets();
        uint256 bobBalAfter = asset.balanceOf(bob);

        // assertions
        assertEq(totAssetsAfter, totAssetsBefore - amountWith);
        assertEq(bobBalAfter, bobBalBefore + amountWith);
    }

    function test_protocol_harvest() public {
        deal(address(asset), bob, 100000e18);
        uint256 amountDep = 100000e18;
        uint256 amountWith = 8;

        // EXECUTE DEPOSIT        
        vm.startPrank(bob);
        asset.approve(address(adapter), amountDep);
        adapter.deposit(amountDep, bob);

        vm.stopPrank();

        vm.roll(block.number + 1_000_000);
        vm.warp(block.timestamp + 15_000_000);

        uint256 totAssetsBefore = adapter.totalAssets();

        // HARVEST
        adapter.harvest();
    
        uint256 totAssetsAfter = adapter.totalAssets();

        assertEq(IERC20(crv).balanceOf(address(adapter)), 0);
        assertEq(IERC20(cvx).balanceOf(address(adapter)), 0);
        assertEq(IERC20(baseAsset).balanceOf(address(adapter)), 0);

        // total assets has increased
        assertGt(totAssetsAfter, totAssetsBefore);
    }

    function _getCommandInputs(string memory key) internal returns (InputIndex[6] memory inputs) {
        for (uint256 i=0; i<6; i++) {
            bool isDynamic = jsonConfig.readBool(
                string.concat(key, "inputIds[", vm.toString(i), "].isDynamicArray")
            );

            uint256 ind = jsonConfig.readUint(
                string.concat(key, "inputIds[", vm.toString(i), "].index")
            );

            inputs[i] = InputIndex(isDynamic, uint8(ind));
        }
    }

    function _getCommandOutput(string memory key) internal returns (OutputIndex memory output) {
        bool isDynamic = jsonConfig.readBool(string.concat(key, "outputId.isDynamicOutput"));
        uint256 ind = jsonConfig.readUint(string.concat(key, "outputId.index"));

        output = OutputIndex(isDynamic, uint8(ind));
    }

    function _getCommandsFromJson(string memory key) internal returns (bytes32[] memory comms) {
        uint256 numCommands = jsonConfig.readUint(string.concat(".", key, ".numCommands"));

        comms = new bytes32[](numCommands);

        for(uint256 i=0; i<numCommands; i++) {
            string memory k = string.concat(".", key, ".commands[", vm.toString(i), "].");

            Command memory command = abi.decode(
                jsonConfig.parseRaw(string.concat(k, "command")),
                (Command)
            );

            if(command.commandType == 14) {
                comms[i] = encoder.UPDATE_STATE_COMMAND();
            } else {
                InputIndex[6] memory inputs = _getCommandInputs(k);
                OutputIndex memory output = _getCommandOutput(k);

                comms[i] = encoder.encodeCommand(command.signature, uint8(command.commandType), inputs, output, command.target);
            }
        }
    }

    function _encodeCommandState(string memory key) internal returns (bytes[] memory states) {
        uint256 len = jsonConfig.readUint(string.concat(".", key, ".stateLen"));
        states = new bytes[](len);

        for(uint256 i=0; i<len; i++) {
            string memory t = jsonConfig.readString(string.concat(".", key, ".state[", vm.toString(i), "].type"));

            bytes32 ty = keccak256(abi.encode(t));

            string memory valueKey = string.concat(".", key, ".state[", vm.toString(i), "].value");

            if(ty == keccak256(abi.encode("bytes"))) {
                bytes memory v = jsonConfig.readBytes(valueKey);
                
                if(keccak256(v) == keccak256(hex"")) {
                    states[i] = abi.encode(address(adapter));
                } else {
                    states[i] = v;
                }
            } else if (ty == keccak256(abi.encode("uint"))) {
                uint256 v = jsonConfig.readUint(valueKey);
                states[i] = abi.encode(v);
            } else if (ty == keccak256(abi.encode("uint[][]"))) {
                uint256 numRows = jsonConfig.readUint(string.concat(".", key, ".state[", vm.toString(i), "].numRows"));

                for(uint256 j=0; j<numRows; j++) {
                    // .value[j]
                    string memory rowKey = string.concat(valueKey, "[", vm.toString(j), "]");
                    uint256[] memory rowValue = jsonConfig.readUintArray(rowKey);
                    // concat encoded rows
                    states[i] = abi.encodePacked(states[i], rowValue);
                }   
            } else if (ty == keccak256(abi.encode("bool"))) {
                bool v = jsonConfig.readBool(valueKey);
                states[i] = abi.encode(v);
            } else if (ty == keccak256(abi.encode("address"))) {
                address v = jsonConfig.readAddress(valueKey);
                states[i] = abi.encode(v);
            } else if (ty == keccak256(abi.encode("address[]"))) {
                address[] memory v = jsonConfig.readAddressArray(valueKey);
                bool isFixedSize = jsonConfig.readBool(string.concat(".", key, ".state[", vm.toString(i), "].fixedSize"));
                
                // encode either as dynamic array or as fixed size
                states[i] = isFixedSize ? abi.encodePacked(v) : abi.encode(v);
            }
        }
    }

    function _totalAssetsCommand() internal returns (bytes32[] memory comm, bytes[] memory states) {
        comm = _getCommandsFromJson("totalAssets");
        states = _encodeCommandState("totalAssets");
    }

    function _depositCommand() internal returns (bytes32[] memory comm, bytes[] memory states) {
        comm = _getCommandsFromJson("deposit");
        states = _encodeCommandState("deposit");
    }

    function _withdrawCommand() internal returns (bytes32[] memory comm, bytes[] memory states) {
        comm = _getCommandsFromJson("withdraw");
        states = _encodeCommandState("withdraw");
    }
    
    function _harvestCommand() internal returns (bytes32[] memory comm, bytes[] memory states) {
        comm = _getCommandsFromJson("harvest");
        states = _encodeCommandState("harvest");
    }

    function _updateStateCommand() internal returns (bytes32 comm) {
        // add info on how to update state on last state slot 
        uint8[] memory updateIndices = new uint8[](2);
        updateIndices[0] = 15; // 
        updateIndices[1] = 14; // update state[14] value
        
        uint8 overwriteIndex = 14; // overwrite the new value to state[14]

        claimStates[claimStates.length - 1] = abi.encode(updateIndices, true, overwriteIndex);
        
        comm = encoder.UPDATE_STATE_COMMAND();
    }
}
