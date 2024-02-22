// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {ConvexAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IConvexBooster, IConvexRewards, IWithRewards, IStrategy} from "../../../../src/vault/adapter/convex/ConvexAdapter.sol";
import {ConvexTestConfigStorage, ConvexTestConfig} from "../convex/ConvexTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../utils/mocks/MockStrategyClaimer.sol";
import {WeirollUniversalAdapter, VmCommand, WeirollReader, Command} from "../../../../src/vault/adapter/abstracts/WeirollAdapter.sol";
import "forge-std/console.sol";

// bytes4 sig = "0x43a0d066"; bytes4(keccak256(abi.encodePacked("deposit(address,address,uint256)")))
// bytes1 f = "0x01"; ->  call 
// bytes6 in = 01 00 02 ff ff ff -> (first arg (pid) at slot 1 in state, second arg(amount) at slot 0, 3 arg(stake) at slot 2); ff to ignore rest of inputs
// bytes1 o = ff -> ignore output 
// bytes20 target = F403C135812408BFbE8713b5A23a04b3D48AAE31; convex booster 
// bytes32 depositBoosterCommand = hex"43a0d06601010002ffffffffF403C135812408BFbE8713b5A23a04b3D48AAE31";

contract WeirollAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IConvexBooster convexBooster =
        IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IConvexRewards convexRewards;
    uint256 pid;
    WeirollUniversalAdapter adapterContract;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

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

        vm.label(address(convexBooster), "convexBooster");
        // vm.label(address(convexRewards), "convexRewards");
        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        // ENCODE TOTAL ASSET 
        // bytes32 totalAssetCommand = hex"70 a0 82 31 02 00 ff ff ff ff ff 0179579633029a61963eDfbA1C0BE22498b6e0D33D";
        bytes32 totalAssetCommand = hex"70a082310200ffffffffff0179579633029a61963eDfbA1C0BE22498b6e0D33D";

        bytes32[] memory tComm = new bytes32[](1);
        tComm[0] = totalAssetCommand;
       
        bytes[] memory tStates = new bytes[](1);
        tStates[0] = abi.encode(address(adapter));

        // ENCODE DEPOSIT 
        bytes32 depositBoosterCommand = hex"43a0d06601020004ffffffffF403C135812408BFbE8713b5A23a04b3D48AAE31";
        // bytes32 safeTransferAssetCommand = hex"23b872dd01010400ffffffff625E92624Bc2D88619ACCc1788365A69767f6200";
        bytes32[] memory depCommands = new bytes32[](1);
        // depCommands[0] = safeTransferAssetCommand;
        depCommands[0] = depositBoosterCommand;
  
        bytes[] memory states = new bytes[](3);
        states[0] = abi.encode(289);
        states[1] = abi.encode(true);
        states[2] = abi.encode(address(adapter));

        // ENCODE WITHDRAW 
        bytes32 withdrawBoosterCommand = hex"c32e7202010001ffffffffff79579633029a61963eDfbA1C0BE22498b6e0D33D";
        bytes32[] memory wCommands = new bytes32[](1);
        wCommands[0] = withdrawBoosterCommand;
        bytes[] memory wStates = new bytes[](1);
        wStates[0] = abi.encode(false);

        // ENCODE ALL COMMANDS 
        bytes memory commands = abi.encode(depCommands,states,wCommands,wStates,tComm,tStates);

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            commands
        );

        adapterContract = WeirollUniversalAdapter(address(adapter));
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
        uint256 totAssetsBefore = adapterContract.totalAssets();
        uint256 bobBalBefore = asset.balanceOf(bob);

        // EXECUTE DEPOSIT        
        vm.startPrank(bob);
        asset.approve(address(adapter), amount);
        adapter.deposit(amount, bob);
        vm.stopPrank();

        // get data after 
        uint256 totAssetsAfter = adapterContract.totalAssets();
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
        adapterContract.deposit(amountDep, bob);
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

    function test_execute() public {
        WeirollReader r = new WeirollReader();
        // 0x70a082310200ffffffffff0179579633029a61963eDfbA1C0BE22498b6e0D33D
        Command memory c = r.translate(hex"70a082310200ffffffffff0179579633029a61963eDfbA1C0BE22498b6e0D33D");
        console.logBytes4(c.sig);
        console.log(c.callType);

        console.log(c.inputIndexes[0]);
        console.log(c.inputIndexes[1]);
        console.log(c.inputIndexes[2]);
        console.log(c.inputIndexes[3]);
        console.log(c.inputIndexes[4]);
        console.log(c.outputIndex);
        console.log(c.target);

    }
}
