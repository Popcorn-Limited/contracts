// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {ConvexAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IConvexBooster, IConvexRewards, IWithRewards, IStrategy} from "../../../../src/vault/adapter/convex/ConvexAdapter.sol";
import {ConvexTestConfigStorage, ConvexTestConfig} from "../convex/ConvexTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../utils/mocks/MockStrategyClaimer.sol";
import {WeirollUniversalAdapter, VmCommand, WeirollReader, Command, InputIndex, MockTarget} from "../../../../src/vault/adapter/weiroll/WeirollAdapter.sol";
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
    WeirollReader r;

    address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    address baseAsset = address(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E); //crvUSD
    address router = address(0xF0d4c12A5768D806021F80a262B4d39d26C58b8D);
    MockTarget mockTarget; 

    bytes[] claimStates = new bytes[](9);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 19262400);

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
        console.log(_asset);
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

        r = new WeirollReader();
        mockTarget = new MockTarget();
        console.log(address(mockTarget));
        // ENCODE TOTAL ASSET 
        InputIndex[6] memory inputs;
        inputs[0] = InputIndex(false, 0); 
        inputs[1] = InputIndex(false, 255); 
        inputs[2] = InputIndex(false, 255);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);

        bytes32[] memory tComm = new bytes32[](1);
        tComm[0] = r.toByteCommand("balanceOf(address)", 2, inputs, 1, address(0x79579633029a61963eDfbA1C0BE22498b6e0D33D)); // BALANCE OF
        bytes[] memory tStates = new bytes[](1);
        tStates[0] = abi.encode(address(adapter));

        // ---------------------------------------------- 
        // ENCODE DEPOSIT 
        inputs[0] = InputIndex(false, 2); 
        inputs[1] = InputIndex(false, 0); 
        inputs[2] = InputIndex(false, 4);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);
       
        bytes32[] memory depCommands = new bytes32[](1);
        // console.logBytes4(bytes4(keccak256(abi.encodePacked("tryOut(uint256[],uint256)"))));
        depCommands[0] = r.toByteCommand("deposit(uint256,uint256,bool)", 1, inputs, 255, address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31)); // DEPOSIT BOOSTER
        // depCommands[0] = hex"dda18e90018203ffffffffffa0Cb889707d426A7A386870A03bc70d1b0697598";
        // 5c9c18e2018586020788fffff0d4c12a5768d806021f80a262b4d39d26c58b8d
        bytes[] memory states = new bytes[](3); 
        // uint256[5] memory test = [uint256(5),0,0,0,uint256(2)];
        // uint256[] memory test2 = new uint256[](5);
        // test2[0] = 5;
        // test2[4] = 2;
        // console.logBytes(abi.encode(test));
        // console.logBytes(abi.encode(test2));

        // states[1] = abi.encode(10);
        states[0] = abi.encode(289);
        states[1] = abi.encode(true);
        states[2] = abi.encode(address(adapter));

        // ---------------------------------------------- 
        // ENCODE WITHDRAW 
        inputs[0] = InputIndex(false, 0); 
        inputs[1] = InputIndex(false, 1); 
        inputs[2] = InputIndex(false, 255);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);

        bytes32 withdrawBoosterCommand = r.toByteCommand("withdrawAndUnwrap(uint256,bool)", 1, inputs, 255, address(0x79579633029a61963eDfbA1C0BE22498b6e0D33D));
        bytes32[] memory wCommands = new bytes32[](1);
        wCommands[0] = withdrawBoosterCommand;
        bytes[] memory wStates = new bytes[](1);
        wStates[0] = abi.encode(false);

        // ---------------------------------------------- 
        // ENCODE HARVEST
        claimStates[0] = abi.encode(address(adapter)); 
        claimStates[1] = abi.encode(true);
        claimStates[2] = abi.encode(0); // leave empty for balanceOf crv output
        claimStates[3] = abi.encode(0); // leave empty for balanceOf cvx output
        claimStates[4] = abi.encode(address(router)); 

        _addSwapState();

        bytes32[] memory claimComms = new bytes32[](6);
        claimComms[0] =  _claimCommand(); // claim rewards
        claimComms[1] = _getCRVBalanceCommand(); // get balance CRV - write at state[2]
        claimComms[2] = _getCVXBalanceCommand(); // get balance CVX - write at state[3]
        claimComms[3] = _approveCRVCommand();  // APPROVE CVX TO BE TRADED BY CURVE ROUTER 
        claimComms[4] = _approveCVXCommand(); // APPROVE CRV TO BE TRADED BY CURVE ROUTER
        claimComms[5] = _swapCRVCommand(); // swap crv

        // ---------------------------------------------- 
        // ENCODE ALL COMMANDS 
        bytes memory commands = abi.encode(depCommands,states,wCommands,wStates,tComm,tStates,claimComms,claimStates);

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
                console.log("TO", adapter.totalAssets());

        adapter.deposit(amountDep, bob);

        vm.stopPrank();

        vm.roll(block.number + 1_000_000);
        vm.warp(block.timestamp + 15_000_000);

        // get data before
        uint256 totAssetsBefore = adapter.totalAssets();
        console.log("TOT", totAssetsBefore);

        // HARVEST
        console.log("BS", IERC20(crv).balanceOf(address(adapter)));
        adapter.harvest();
        console.log("BS", IERC20(crv).balanceOf(address(adapter)));

        // get data after 
        uint256 totAssetsAfter = adapter.totalAssets();
        // uint256 bobBalAfter = asset.balanceOf(bob);

        // assertions
        assertEq(totAssetsAfter, totAssetsBefore);
        // assertEq(bobBalAfter, bobBalBefore + amountWith);
    }

    function test_reader() public {
        // 0x70a082310200ffffffffff0179579633029a61963eDfbA1C0BE22498b6e0D33D
        Command memory c = r.translate(hex"70a082310200ffffffffff0179579633029a61963eDfbA1C0BE22498b6e0D33D");

        InputIndex[6] memory inputs;
        inputs[0] = InputIndex(false, 0);
        inputs[1] = InputIndex(false, 255);
        inputs[2] = InputIndex(false, 255);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);

        bytes32 comm = r.toByteCommand("balanceOf(address)", 2, inputs, 1, address(0x79579633029a61963eDfbA1C0BE22498b6e0D33D));
        assertEq(comm, hex"70a082310200ffffffffff0179579633029a61963eDfbA1C0BE22498b6e0D33D");
    }

    function _claimCommand() internal returns (bytes32 comm) {
        InputIndex[6] memory inputs;
        inputs[0] = InputIndex(false, 0);
        inputs[1] = InputIndex(false, 1);
        inputs[2] = InputIndex(false, 255);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);
        
        // 0x7050ccd9 01 00 01 ff ff ff ff ff 79579633029a61963edfba1c0be22498b6e0d33d
        comm = r.toByteCommand("getReward(address,bool)", 1, inputs, 255, address(0x79579633029a61963eDfbA1C0BE22498b6e0D33D));
    }

    function _getCRVBalanceCommand() internal returns (bytes32 comm) {
        InputIndex[6] memory inputs;
        inputs[0] = InputIndex(false, 0);
        inputs[1] = InputIndex(false, 255);
        inputs[2] = InputIndex(false, 255);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);

        comm = r.toByteCommand("balanceOf(address)", 2, inputs, 2, crv);
    }

    function _getCVXBalanceCommand() internal returns (bytes32 comm) {
        InputIndex[6] memory inputs;
        inputs[0] = InputIndex(false, 0);
        inputs[1] = InputIndex(false, 255);
        inputs[2] = InputIndex(false, 255);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);
        
        comm = r.toByteCommand("balanceOf(address)", 2, inputs, 3, cvx);
    }

    function _approveCRVCommand() internal returns (bytes32 comm) {
        InputIndex[6] memory inputs;
        inputs[0] = InputIndex(false, 4); // address(router)
        inputs[1] = InputIndex(false, 2); // amount is writtem at state slot 2 as output
        inputs[2] = InputIndex(false, 255);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);

        comm = r.toByteCommand("approve(address,uint256)", 1, inputs, 255, crv);
    }

    function _approveCVXCommand() internal returns (bytes32 comm) {
        InputIndex[6] memory inputs;
        inputs[0] = InputIndex(false, 4); // address(router)
        inputs[1] = InputIndex(false, 3); // amount is writtem at state slot 2 as output
        inputs[2] = InputIndex(false, 255);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);
        
        comm = r.toByteCommand("approve(address,uint256)", 1, inputs, 255, cvx);
    }

    // // Lenght of the array + its elements as state slot of a dynamic var 
    // states[0] = abi.encodePacked(test2.length, test2);
    function _addSwapState() internal {
        address[11] memory rewardRoute = [
            crv, // crv
            0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14, // triCRV pool
            0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E, // crvUSD
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        ];
        address[5] memory pools = [
            address(0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14),
            address(0),
            address(0),
            address(0),
            address(0)
        ];


        uint256[5][5] memory swapParams0;
        swapParams0[0] = [uint256(2), 0, 1, 1, 2];

        // add states
        claimStates[5] = abi.encodePacked(rewardRoute.length, rewardRoute);
        // console.logBytes(claimStates[5]);
        claimStates[6] = abi.encode(swapParams0.length, swapParams0);
        claimStates[7] = abi.encode(0);
        claimStates[8] = abi.encode(pools.length, pools);
    }

    function _swapCRVCommand() internal returns (bytes32 comm) {
        uint8[6] memory inputsInd;
        inputsInd[0] = 5;
        inputsInd[1] = 6;
        inputsInd[2] = 2;
        inputsInd[3] = 7;
        inputsInd[4] = 8;
        inputsInd[5] = 255;
        
        console.log("HE");
        console.logBytes4(bytes4(keccak256(abi.encodePacked("exchange(address[11],uint256[5][5],uint256,uint256,address[5])"))));

        // comm = r.toByteCommand("exchange(address[11],uint256[5][5],uint256,uint256,address[5])", 1, true, inputsInd, 255, address(0xF0d4c12A5768D806021F80a262B4d39d26C58b8D));
        comm = hex"5c9c18e2018586020788fffff0d4c12a5768d806021f80a262b4d39d26c58b8d";
    }
}
