//// SPDX-License-Identifier: GPL-3.0
//// Docgen-SOLC: 0.8.15
//
//pragma solidity ^0.8.15;
//
//import {AcrossAdapter, SafeERC20, IERC20, IERC20Metadata, IAcrossHop, IAcceleratingDistributor, IWithRewards, IStrategy} from "../../../../src/vault/adapter/across/AcrossAdapter.sol";
//import {AcrossTestConfigStorage, AcrossTestConfig} from "./AcrossTestConfigStorage.sol";
//import {AbstractAdapterTest, ITestConfigStorage, IAdapter, Math} from "../abstract/AbstractAdapterTest.sol";
//import {IPermissionRegistry, Permission} from "../../../../src/interfaces/vault/IPermissionRegistry.sol";
//import {PermissionRegistry} from "../../../../src/vault/PermissionRegistry.sol";
//import {MockStrategyClaimer} from "../../../utils/mocks/MockStrategyClaimer.sol";
//
//contract AcrossAdapterTest is AbstractAdapterTest {
//    using Math for uint256;
//
//    // Mainnet Across L1 token - 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 // WETH
//    address public l1Token = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
//    address public acrossHop;
//    address public acrossDistributor;
//
//    IPermissionRegistry permissionRegistry;
//
//    function setUp() public {
//        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
//        vm.selectFork(forkId);
//        testConfigStorage = ITestConfigStorage(
//            address(new AcrossTestConfigStorage())
//        );
//
//        _setUpTest(testConfigStorage.getTestConfig(0));
//    }
//
//    function overrideSetup(bytes memory testConfig) public override {
//        _setUpTest(testConfig);
//    }
//
//    function _setUpTest(bytes memory testConfig) internal {
//        createAdapter();
//
//        (address _acrossHop, address _acrossDistributor) = abi.decode(
//            testConfig,
//            (address, address)
//        );
//
//        acrossHop = _acrossHop;
//        acrossDistributor = _acrossDistributor;
//
//        // Endorse acrossMarket
//        permissionRegistry = IPermissionRegistry(
//            address(new PermissionRegistry(address(this)))
//        );
//        setPermission(acrossHop, true, false);
//        setPermission(acrossDistributor, true, false);
//
//        vm.label(acrossHop, "acrossHop");
//        vm.label(acrossDistributor, "acrossDistributor");
//
//        setUpBaseTest(
//            IERC20(l1Token),
//            address(new AcrossAdapter()),
//            address(permissionRegistry),
//            10,
//            "Across ",
//            true
//        );
//
//        adapter.initialize(
//            abi.encode(l1Token, address(this), strategy, 0, sigs, ""),
//            externalRegistry,
//            testConfig
//        );
//    }
//
//    /*//////////////////////////////////////////////////////////////
//                          HELPER
//    //////////////////////////////////////////////////////////////*/
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
//        permissionRegistry.setPermissions(targets, permissions);
//    }
//
//    function increasePricePerShare(uint256 amount) public override {
//        deal(address(asset), acrossHop, asset.balanceOf(acrossHop) + amount);
//    }
//
//    // Verify that totalAssets returns the expected amount
//    function verify_totalAssets() public override {
//        // Make sure totalAssets isnt 0
//        deal(address(asset), bob, defaultAmount);
//        vm.startPrank(bob);
//        asset.approve(address(adapter), defaultAmount);
//        adapter.deposit(defaultAmount, bob);
//        vm.stopPrank();
//
//        assertEq(
//            adapter.totalAssets(),
//            adapter.convertToAssets(adapter.totalSupply()),
//            string.concat("totalSupply converted != totalAssets", baseTestId)
//        );
//    }
//
//    /*//////////////////////////////////////////////////////////////
//                          INITIALIZATION
//    //////////////////////////////////////////////////////////////*/
//
//    function verify_adapterInit() public override {
//        assertEq(adapter.asset(), address(asset), "asset");
//        assertEq(
//            IERC20Metadata(address(adapter)).name(),
//            string.concat(
//                "VaultCraft Across ",
//                IERC20Metadata(address(asset)).name(),
//                " Adapter"
//            ),
//            "name"
//        );
//        assertEq(
//            IERC20Metadata(address(adapter)).symbol(),
//            string.concat("vcAxc-", IERC20Metadata(address(asset)).symbol()),
//            "symbol"
//        );
//
//        assertEq(
//            asset.allowance(address(adapter), address(acrossHop)),
//            type(uint256).max,
//            "allowance"
//        );
//    }
//
//    /*//////////////////////////////////////////////////////////////
//                                PAUSE
//    //////////////////////////////////////////////////////////////*/
//
//    function test__unpause() public override {
//        _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);
//
//        vm.prank(bob);
//        adapter.deposit(defaultAmount, bob);
//
//        uint256 oldTotalAssets = adapter.totalAssets();
//        uint256 oldTotalSupply = adapter.totalSupply();
//        uint256 oldIouBalance = iouBalance();
//
//        adapter.pause();
//        adapter.unpause();
//
//        // We simply deposit back into the external protocol
//        // TotalSupply and Assets dont change
//        // @dev overriden _delta_
//        assertApproxEqAbs(
//            oldTotalAssets,
//            adapter.totalAssets(),
//            50,
//            "totalAssets"
//        );
//        assertApproxEqAbs(
//            oldTotalSupply,
//            adapter.totalSupply(),
//            50,
//            "totalSupply"
//        );
//        assertApproxEqAbs(
//            asset.balanceOf(address(adapter)),
//            0,
//            50,
//            "asset balance"
//        );
//        assertApproxEqAbs(iouBalance(), oldIouBalance, 50, "iou balance");
//
//        // Deposit and mint dont revert
//        vm.startPrank(bob);
//        adapter.deposit(defaultAmount, bob);
//        adapter.mint(defaultAmount, bob);
//    }
//
//    /*//////////////////////////////////////////////////////////////
//                              CLAIM
//    //////////////////////////////////////////////////////////////*/
//
//    function test__claim() public override {
//        strategy = IStrategy(address(new MockStrategyClaimer()));
//        createAdapter();
//        adapter.initialize(
//            abi.encode(asset, address(this), strategy, 0, sigs, ""),
//            externalRegistry,
//            testConfigStorage.getTestConfig(0)
//        );
//        _mintAssetAndApproveForAdapter(1000e18, bob);
//        vm.prank(bob);
//        adapter.deposit(1000e18, bob);
//        vm.warp(block.timestamp + 10 days);
//        vm.prank(bob);
//        adapter.withdraw(1, bob, bob);
//        address[] memory rewardTokens = IWithRewards(address(adapter))
//            .rewardTokens();
//        assertGt(IERC20(rewardTokens[0]).balanceOf(address(adapter)), 0);
//    }
//
//    function test__harvest() public override {
//        uint256 performanceFee = 1e16;
//        uint256 hwm = 1e9;
//
//        _mintAssetAndApproveForAdapter(defaultAmount, bob);
//
//        vm.prank(bob);
//        adapter.deposit(defaultAmount, bob);
//
//        uint256 oldTotalAssets = adapter.totalAssets();
//        address lpToken = IAcrossHop(acrossHop)
//            .pooledTokens(address(asset))
//            .lpToken;
//        adapter.setPerformanceFee(performanceFee);
//
//        increasePricePerShare(raise);
//
//        deal(
//            lpToken,
//            acrossDistributor,
//            IERC20(lpToken).balanceOf(acrossDistributor) - 10 ** 18,
//            true
//        );
//
//        uint256 gain = ((adapter.convertToAssets(1e18) -
//            adapter.highWaterMark()) * adapter.totalSupply()) / 1e18;
//        uint256 fee = (gain * performanceFee) / 1e18;
//
//        uint256 expectedFee = adapter.convertToShares(fee);
//
//        vm.expectEmit(false, false, false, true, address(adapter));
//
//        emit Harvested();
//
//        adapter.harvest();
//
//        // Multiply with the decimal offset
//        assertApproxEqAbs(
//            adapter.totalSupply(),
//            defaultAmount * 1e9 + expectedFee,
//            _delta_,
//            "totalSupply"
//        );
//        assertApproxEqAbs(
//            adapter.balanceOf(feeRecipient),
//            expectedFee,
//            _delta_,
//            "expectedFee"
//        );
//    }
//}
