// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {ConvexAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IConvexBooster, IConvexRewards, IWithRewards, IStrategy} from "../../../../../src/vault/adapter/convex/ConvexAdapter.sol";
import {ConvexTestConfigStorage, ConvexTestConfig} from "../../convex/ConvexTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../../utils/mocks/MockStrategyClaimer.sol";
import {WeirollUniversalAdapter, VmCommand} from "../../../../../src/vault/adapter/weiroll/WeirollAdapter.sol";
import {WeirollBuilder} from "../../../../../src/vault/adapter/weiroll/WeirollUtils.sol";
import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/console.sol";

contract WeirollAdapterTest is AbstractAdapterTest {
    using Math for uint256;
    using stdJson for string;
    using WeirollBuilder for string;

    address extRegistryToApprove = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31); // convex booster

    IConvexRewards convexRewards;
    address rewardPool = address(0x79579633029a61963eDfbA1C0BE22498b6e0D33D);

    address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    address baseAsset = address(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E); //crvUSD
    address assetAddr = address(0x625E92624Bc2D88619ACCc1788365A69767f6200); // crvUSD lp token

    string jsonConfig;
    string jsonPath = "/test/vault/adapter/weiroll-implementations/convex/ConvexCompounderConfig.json";

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 19262400);

        jsonConfig = vm.readFile(
            string.concat(
                vm.projectRoot(),
                jsonPath
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
        // convexRewards = IConvexRewards(_convexRewards);

        setUpBaseTest(
            IERC20(assetAddr),
            address(new WeirollUniversalAdapter()),
            extRegistryToApprove,
            10,
            "Convex",
            true
        );
        
        vm.prank(address(this));

        vm.label(extRegistryToApprove, "convexBooster");
        // vm.label(address(convexRewards), "convexRewards");
        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        uint256 stateLen;
        uint256 commandLen;

        // ENCODE TOTAL ASSET 
        (commandLen, stateLen) = jsonConfig.getCommandAndStateLength("totalAssets");
        bytes32[] memory tComm = new bytes32[](commandLen);
        bytes[] memory tStates = new bytes[](stateLen);
        (tComm, tStates) = jsonConfig.getCommandsAndState("totalAssets");

        // ---------------------------------------------- 
        // ENCODE DEPOSIT
        (commandLen, stateLen) = jsonConfig.getCommandAndStateLength("deposit");         
        bytes32[] memory depCommands = new bytes32[](commandLen);
        bytes[] memory depStates = new bytes[](stateLen);
        (depCommands, depStates) = jsonConfig.getCommandsAndState("deposit");

        // ---------------------------------------------- 
        // ENCODE WITHDRAW 
        (commandLen, stateLen) = jsonConfig.getCommandAndStateLength("withdraw");         
        bytes32[] memory wCommands = new bytes32[](commandLen);
        bytes[] memory wStates = new bytes[](stateLen);
        (wCommands, wStates) = jsonConfig.getCommandsAndState("withdraw");

        // ---------------------------------------------- 
        // ENCODE HARVEST
        (commandLen, stateLen) = jsonConfig.getCommandAndStateLength("harvest");      
        bytes32[] memory claimComms = new bytes32[](commandLen);
        bytes[] memory claimStates = new bytes[](stateLen);   
        (claimComms, claimStates) = jsonConfig.getCommandsAndState("harvest");

        // TODO this needs to be encoded as well in the json
        // add info on how to update state on last state slot 
        uint8[] memory updateIndices = new uint8[](2);
        updateIndices[0] = 15; // 
        updateIndices[1] = 14; // update state[14] value
        
        uint8 overwriteIndex = 14; // overwrite the new value to state[14]

        claimStates[claimStates.length - 1] = abi.encode(updateIndices, true, overwriteIndex);

        // ---------------------------------------------- 
        // ENCODE ALL COMMANDS 
        bytes memory commands = abi.encode(depCommands,depStates,wCommands,wStates,tComm,tStates,claimComms,claimStates);

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            commands
        );

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
            asset.allowance(address(adapter), extRegistryToApprove),
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
        uint256 totAssetsBefore = adapter.totalAssets();
        uint256 bobBalBefore = asset.balanceOf(bob);

        // EXECUTE WITHDRAW        
        vm.prank(bob);
        adapter.withdraw(amountWith, bob, bob);

        // get data after 
        uint256 totAssetsAfter = adapter.totalAssets();
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
}
