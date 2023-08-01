// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {
    Test
} from "forge-std/Test.sol";
import {
    Y2kTestConfig,
    Y2kTestConfigStorage
} from "../Y2kTestConfigStorage.sol";
import {
    IAdapter,
    ITestConfigStorage,
    AbstractAdapterTest
} from "../../abstract/AbstractAdapterTest.sol";
import {
    PermissionRegistry
} from "../../../../../src/vault/PermissionRegistry.sol";
import {
    Permission,
    IPermissionRegistry
} from "../../../../../src/interfaces/vault/IPermissionRegistry.sol";
import {
    Math,
    IERC20,
    SafeERC20,
    ICarousel,
    IERC20Metadata,
    ICarouselFactory,
    Y2KPremiumAdapter
} from "../../../../../src/vault/adapter/y2k/premium/Y2KPremiumAdapter.sol";
import "forge-std/console.sol";


contract Y2kPremiumAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    ICarousel public carousel;
    ICarouselFactory public carouselFactory;
    IPermissionRegistry public permissionRegistry;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("arbitrum"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new Y2kTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _carouselFactory, uint256 _marketId) = abi.decode(testConfig, (address, uint256));

        carouselFactory = ICarouselFactory(_carouselFactory);
        address[2] memory vaults = carouselFactory.getVaults(_marketId);
        carousel = ICarousel(vaults[0]);

        permissionRegistry = IPermissionRegistry(
            address(new PermissionRegistry(address(this)))
        );
        setPermission(address(carouselFactory), true, false);

        setUpBaseTest(
            IERC20(carousel.asset()),
            address(new Y2KPremiumAdapter()),
            address(permissionRegistry),
            10,
            "Y2K",
            true
        );

        vm.label(address(carousel.asset()), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(carousel.asset(), address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/
    function setPermission(
        address target,
        bool endorsed,
        bool rejected
    ) public {
        address[] memory targets = new address[](1);
        Permission[] memory permissions = new Permission[](1);
        targets[0] = target;
        permissions[0] = Permission(endorsed, rejected);
        permissionRegistry.setPermissions(targets, permissions);
    }

    function _getLatestEpochId(ICarousel _carousel) internal view returns(uint256 epochId) {
        epochId = _carousel.epochs(_carousel.getEpochsLength() - 1);
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), address(asset), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Y2k Premium ",//TODO: add the name of the y2k vault here
                "Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            "vcY2kPremium",
            "symbol"
        );
    }

    /*//////////////////////////////////////////////////////////////
                              HARVEST
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public override {
        // There is no strategy to harvest from
    }

    /*//////////////////////////////////////////////////////////////
                              PAUSE
    //////////////////////////////////////////////////////////////*/

    function test__pause() public override {
        uint256 val = adapter.maxWithdraw(bob);
        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();

        adapter.pause();

        // We simply withdraw into the adapter
        // TotalSupply and Assets dont change
        assertApproxEqAbs(
            oldTotalAssets,
            adapter.totalAssets(),
            _delta_,
            "totalAssets"
        );
        assertApproxEqAbs(
            oldTotalSupply,
            adapter.totalSupply(),
            _delta_,
            "totalSupply"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(adapter)),
            oldTotalAssets,
            _delta_,
            "asset balance"
        );
        assertApproxEqAbs(iouBalance(), 0, _delta_, "iou balance");

        vm.startPrank(bob);
        // Deposit and mint are paused (maxDeposit/maxMint are set to 0 on pause)
        vm.expectRevert();
        adapter.deposit(defaultAmount, bob);

        vm.expectRevert();
        adapter.mint(defaultAmount, bob);

        // Withdraw and Redeem dont revert
        //adapter.withdraw(defaultAmount / 10, bob, bob);
        //        adapter.redeem(defaultAmount / 10, bob, bob);
    }

    function test__withdraw(uint8 fuzzAmount) public override {
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            vm.warp(block.timestamp - 7 days);

            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));
            uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

            uint256 reqAssets = adapter.previewMint(
                adapter.previewWithdraw(amount)
            ) * 10;
            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);
            adapter.deposit(reqAssets, bob);

            vm.warp(block.timestamp + 7 days);
            address controller = carousel.controller();
            uint256 epochId = _getLatestEpochId(carousel);

            vm.prank(controller);
            carousel.resolveEpoch(epochId);
            vm.prank(controller);
            carousel.setEpochNull(epochId);

            vm.prank(bob);
            prop_withdraw(bob, bob, amount / 10, testId);


            //            _mintAssetAndApproveForAdapter(reqAssets, bob);
            //            vm.prank(bob);
            //            adapter.deposit(reqAssets, bob);
            //
            //            increasePricePerShare(raise);
            //
            //            vm.prank(bob);
            //            adapter.approve(alice, type(uint256).max);
            //
            //            prop_withdraw(alice, bob, amount, testId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test__RT_deposit_redeem() public override {
        _mintAssetAndApproveForAdapter(defaultAmount, bob);
        vm.warp(block.timestamp - 7 days);

        vm.startPrank(bob);
        uint256 shares = adapter.deposit(defaultAmount, bob);
        vm.warp(block.timestamp + 7 days);

        address controller = carousel.controller();
        uint256 epochId = _getLatestEpochId(carousel);
        vm.prank(controller);
        carousel.resolveEpoch(epochId);
        vm.prank(controller);
        carousel.setEpochNull(epochId);

        vm.prank(bob);
        uint256 assets = adapter.redeem(defaultAmount, bob, bob);

        // Pass the test if maxRedeem is smaller than deposit since round trips are impossible
        if (adapter.maxRedeem(bob) == defaultAmount) {
            assertLe(assets, defaultAmount, testId);
        }
    }

    function test__RT_deposit_withdraw() public override {
        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.startPrank(bob);
        vm.warp(block.timestamp - 7 days);
        uint256 shares1 = adapter.deposit(defaultAmount, bob);
        vm.warp(block.timestamp + 7 days);

        address controller = carousel.controller();
        uint256 epochId = _getLatestEpochId(carousel);

        vm.prank(controller);
        carousel.resolveEpoch(epochId);
        vm.prank(controller);
        carousel.setEpochNull(epochId);

        vm.prank(bob);
        uint256 shares2 = adapter.withdraw(defaultAmount, bob, bob);
        vm.stopPrank();

        // Pass the test if maxWithdraw is smaller than deposit since round trips are impossible
        if (adapter.maxWithdraw(bob) == defaultAmount) {
            assertGe(shares2, shares1, testId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          PREVIEW VIEWS
    //////////////////////////////////////////////////////////////*/
    function test__previewRedeem(uint8 fuzzAmount) public override {
        uint256 amount = bound(uint256(fuzzAmount), minShares, maxShares);

        uint256 reqAssets = adapter.previewMint(amount) * 10;
        _mintAssetAndApproveForAdapter(reqAssets, bob);
        vm.prank(bob);

        vm.warp(block.timestamp - 7 days);
        adapter.deposit(reqAssets, bob);
        vm.warp(block.timestamp + 7 days);

        address controller = carousel.controller();
        uint256 epochId = _getLatestEpochId(carousel);

        vm.prank(controller);
        carousel.resolveEpoch(epochId);
        vm.prank(controller);
        carousel.setEpochNull(epochId);

        vm.prank(bob);
        prop_previewRedeem(bob, bob, bob, amount, testId);
    }

    function test__previewWithdraw(uint8 fuzzAmount) public override {
        uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

        uint256 reqAssets = adapter.previewMint(
            adapter.previewWithdraw(amount)
        ) * 10;

        _mintAssetAndApproveForAdapter(reqAssets, bob);
        vm.prank(bob);

        vm.warp(block.timestamp - 7 days);
        adapter.deposit(reqAssets, bob);
        vm.warp(block.timestamp + 7 days);

        address controller = carousel.controller();
        uint256 epochId = _getLatestEpochId(carousel);

        vm.prank(controller);
        carousel.resolveEpoch(epochId);
        vm.prank(controller);
        carousel.setEpochNull(epochId);

        vm.prank(bob);

        prop_previewWithdraw(bob, bob, bob, amount, testId);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/MINT/WITHDRAW/REDEEM
    //////////////////////////////////////////////////////////////*/
    function test__redeem(uint8 fuzzAmount) public override {
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));
            uint256 amount = bound(uint256(fuzzAmount), minShares, maxShares);

            uint256 reqAssets = adapter.previewMint(amount) * 10;
            _mintAssetAndApproveForAdapter(reqAssets, bob);

            vm.prank(bob);
            vm.warp(block.timestamp - 7 days);
            adapter.deposit(reqAssets, bob);
            vm.warp(block.timestamp + 7 days);

            address controller = carousel.controller();
            uint256 epochId = _getLatestEpochId(carousel);

            vm.prank(controller);
            carousel.resolveEpoch(epochId);
            vm.prank(controller);
            carousel.setEpochNull(epochId);

            prop_redeem(bob, bob, amount, testId);

            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);
            adapter.deposit(reqAssets, bob);

            increasePricePerShare(raise);

            vm.prank(bob);
            adapter.approve(alice, type(uint256).max);
            prop_redeem(alice, bob, amount, testId);
        }
    }
}
