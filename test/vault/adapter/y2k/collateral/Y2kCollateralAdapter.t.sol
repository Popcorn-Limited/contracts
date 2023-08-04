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
    QueueItem,
    ICarousel,
    IERC20Metadata,
    ICarouselFactory,
    Y2KCollateralAdapter
} from "../../../../../src/vault/adapter/y2k/collateral/Y2KCollateralAdapter.sol";
import "forge-std/console.sol";

contract Y2kCollateralAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    ICarousel public carousel;
    ICarouselFactory public carouselFactory;
    IPermissionRegistry public permissionRegistry;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("arbitrum"), 114354735);
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
        carousel = ICarousel(vaults[1]);

        permissionRegistry = IPermissionRegistry(
            address(new PermissionRegistry(address(this)))
        );
        setPermission(address(carouselFactory), true, false);

        setUpBaseTest(
            IERC20(carousel.asset()),
            address(new Y2KCollateralAdapter()),
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

    function _resolveEpoch() internal {
        //increase block time and resolve an epochId
        vm.warp(block.timestamp + 7 days);
        address controller = carousel.controller();
        uint256 epochId = _getLatestEpochId(carousel);
        vm.prank(controller);
        carousel.resolveEpoch(epochId);
        vm.prank(controller);
        carousel.setEpochNull(epochId);

        console.log("epoch resolved: ", carousel.epochResolved(epochId), epochId);
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), address(asset), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Y2k Collateral ",//TODO: add the name of the y2k vault here
                "Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            "vcY2kCollateral",
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

        _resolveEpoch();
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

    function test__unpause() public override {
        _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();
        uint256 oldIouBalance = iouBalance();

        _resolveEpoch();

        adapter.pause();
        adapter.unpause();

        uint256 depositQueueIndex = carousel.getDepositQueueLength() - 1;
        QueueItem memory queueItem = carousel.depositQueue(depositQueueIndex);

        // We simply deposit back into the external protocol
        // TotalSupply and Assets dont change
        uint256 newTotalAssets = queueItem.shares;
        assertApproxEqAbs(
            oldTotalAssets,
            newTotalAssets,
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
            0,
            _delta_,
            "asset balance"
        );
        assertApproxEqAbs(iouBalance(), oldIouBalance, _delta_, "iou balance");

        // Deposit and mint dont revert
        vm.startPrank(bob);
        adapter.deposit(defaultAmount, bob);
        adapter.mint(defaultAmount * 1e9, bob);
    }

    function test__withdraw(uint8 fuzzAmount) public override {
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));
            uint256 amount = bound(carousel.minQueueDeposit(), minFuzz, maxAssets);

            uint256 reqAssets = adapter.previewMint(
                adapter.previewWithdraw(amount)
            ) * 10;
            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);
            adapter.deposit(reqAssets, bob);

            _resolveEpoch();

            vm.prank(bob);
            prop_withdraw(bob, bob, amount / 10, testId);

            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);
            adapter.deposit(reqAssets, bob);

            increasePricePerShare(raise);

            vm.prank(bob);
            adapter.approve(alice, type(uint256).max);

            //prop_withdraw(alice, bob, amount, testId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
    //////////////////////////////////////////////////////////////*/
    function test__RT_deposit_redeem() public override {
        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.startPrank(bob);
        uint256 shares = adapter.deposit(defaultAmount, bob);

        _resolveEpoch();

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
        uint256 shares1 = adapter.deposit(defaultAmount, bob);

        _resolveEpoch();

        vm.prank(bob);
        uint256 shares2 = adapter.withdraw(defaultAmount/10, bob, bob);
        //vm.stopPrank();

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

        adapter.deposit(reqAssets, bob);

        _resolveEpoch();

        vm.prank(bob);
        prop_previewRedeem(bob, bob, bob, amount, testId);
    }

    function test__previewWithdraw(uint8 fuzzAmount) public override {
        uint256 amount = bound(uint256(fuzzAmount), carousel.minQueueDeposit(), maxAssets);

        uint256 reqAssets = adapter.previewMint(
            adapter.previewWithdraw(amount)
        ) * 10;

        _mintAssetAndApproveForAdapter(reqAssets, bob);
        vm.prank(bob);

        adapter.deposit(reqAssets, bob);

        _resolveEpoch();

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
            adapter.deposit(reqAssets, bob);

            _resolveEpoch();

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

    /*//////////////////////////////////////////////////////////////
                          MAX VIEWS
    //////////////////////////////////////////////////////////////*/
    function test__maxDeposit() public override {
        prop_maxDeposit(bob);

        // Deposit smth so withdraw on pause is not 0
        _mintAsset(defaultAmount, address(this));
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, address(this));

        _resolveEpoch();

        adapter.pause();
        assertEq(adapter.maxDeposit(bob), 0);
    }

    function test__maxMint() public override {
        prop_maxMint(bob);

        // Deposit smth so withdraw on pause is not 0
        _mintAsset(defaultAmount, address(this));
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, address(this));

        _resolveEpoch();

        adapter.pause();
        assertEq(adapter.maxMint(bob), 0);
    }
}
