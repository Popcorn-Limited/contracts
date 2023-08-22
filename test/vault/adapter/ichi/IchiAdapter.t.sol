// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {IchiAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IVault, IVaultFactory, IDepositGuard, IUniV3Pool, IStrategy, IAdapter, IWithRewards} from "../../../../src/vault/adapter/ichi/IchiAdapter.sol";
import {IchiTestConfigStorage, IchiTestConfig} from "./IchiTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage} from "../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../utils/mocks/MockStrategyClaimer.sol";
import {MockStrategy} from "../../../utils/mocks/MockStrategy.sol";
import {UniswapV3Utils} from "src/utils/UniswapV3Utils.sol";

// TODO: 12 of Ichi's tests fail. Main cause is the withdrawal of funds which reverts because the contract
// doesn't get enough tokens back from the Ichi vault to pay back the user.
contract IchiAdapterTestSkip is AbstractAdapterTest {
    using Math for uint256;

    address public ichi;
    IVault public vault;
    IDepositGuard public depositGuard;
    IVaultFactory public vaultFactory;
    address public vaultDeployer;
    uint256 public pid;
    uint8 public assetIndex;
    address public uniRouter;
    IUniV3Pool public uniPool;
    uint24 public uniSwapFee;
    uint256 public slippage;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("polygon"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new IchiTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (
            uint256 _pid,
            address _depositGuard,
            address _vaultDeployer,
            address _uniRouter,
            uint24 _uniSwapFee,
            uint256 _slippage
        ) = abi.decode(
                testConfig,
                (uint256, address, address, address, uint24, uint256)
            );

        pid = _pid;
        vaultDeployer = _vaultDeployer;
        uniRouter = _uniRouter;
        uniSwapFee = _uniSwapFee;

        slippage = _slippage;

        depositGuard = IDepositGuard(_depositGuard);
        vaultFactory = IVaultFactory(depositGuard.ICHIVaultFactory());
        vault = IVault(vaultFactory.allVaults(pid));
        uniPool = IUniV3Pool(vault.pool());

        assetIndex = vault.token0() == address(asset) ? 0 : 1;
        address token0 = vault.token0();
        address token1 = vault.token1();
        asset = assetIndex == 0 ? IERC20(token0) : IERC20(token1);

        setUpBaseTest(
            IERC20(asset),
            address(new IchiAdapter()),
            address(vaultFactory),
            10,
            "Ichi",
            true
        );

        vm.label(address(vaultFactory), "vaultFactory");
        vm.label(address(asset), "asset");
        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );

        defaultAmount = 1e18;

        minFuzz = 1e18;
        minShares = 1e27;

        raise = defaultAmount * 100_000;

        maxAssets = minFuzz * 10;
        maxShares = minShares * 10;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        deal(address(asset), bob, defaultAmount);
        vm.startPrank(bob);
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, bob);
        vm.stopPrank();

        assertEq(
            adapter.totalAssets(),
            adapter.convertToAssets(adapter.totalSupply()),
            string.concat("totalSupply converted != totalAssets", baseTestId)
        );
    }

    function generateUniV3Fees() public {
        address charlie = 0x409F5E7c126275566C3092F0cDB8D5b6820446BC;
        address weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
        address usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
        address uniRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        uint24 uniSwapFee = 500;
        uint256 amount = 1000e18;
        uint24 swapCycles = 5000;

        deal(weth, charlie, amount);

        vm.startPrank(charlie);

        uint256 wethBalBefore = IERC20(weth).balanceOf(charlie);
        uint256 usdcBalBefore = IERC20(usdc).balanceOf(charlie);

        emit log_named_uint("weth balance before", wethBalBefore);
        emit log_named_uint("usdc balance before", usdcBalBefore);

        IERC20(weth).approve(uniRouter, type(uint256).max);
        IERC20(usdc).approve(uniRouter, type(uint256).max);

        bool wethToUsdc = true;
        for (uint256 i; i < swapCycles; ++i) {
            address tokenIn = wethToUsdc ? weth : usdc;
            address tokenOut = wethToUsdc ? usdc : weth;
            uint256 amountIn = wethToUsdc
                ? IERC20(weth).balanceOf(charlie)
                : IERC20(usdc).balanceOf(charlie);

            UniswapV3Utils.swap(
                uniRouter,
                charlie,
                tokenIn,
                tokenOut,
                uniSwapFee,
                amountIn
            );

            wethToUsdc = !wethToUsdc;
        }

        uint256 wethBalAfter = IERC20(weth).balanceOf(charlie);
        uint256 usdcBalAfter = IERC20(usdc).balanceOf(charlie);

        emit log_named_uint("weth balance after", wethBalAfter);
        emit log_named_uint("usdc balance after", usdcBalAfter);

        if (wethBalAfter > usdcBalAfter) {
            emit log_named_uint(
                "weth sent to pool",
                wethBalBefore - wethBalAfter
            );
        } else {
            emit log_named_uint(
                "usdc sent to pool",
                usdcBalBefore - usdcBalAfter
            );
        }

        vm.stopPrank();
    }

    function distributeIchiFees() public {
        address _ichiVault = 0xB05bE549a570e430e5ddE4A10a0d34cf09a7df21;
        IVault ichiVault = IVault(_ichiVault);

        address owner = ichiVault.owner();

        vm.startPrank(owner);

        int24 baseLower = ichiVault.baseLower();
        int24 baseUpper = ichiVault.baseUpper();
        int24 limitLower = ichiVault.limitLower();
        int24 limitUpper = ichiVault.limitUpper();
        int256 swapQuantity = 0;

        ichiVault.rebalance(
            baseLower,
            baseUpper,
            limitLower,
            limitUpper,
            swapQuantity
        );

        vm.stopPrank();
    }

    function increasePricePerShare(uint256 amount) public override {
        generateUniV3Fees();
        distributeIchiFees();
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), address(asset), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Ichi ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcIchi-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(depositGuard)),
            type(uint256).max,
            "allowance"
        );
    }

    function test__harvest() public override {
        uint256 performanceFee = 1e16;
        uint256 hwm = 1e9;

        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        adapter.setPerformanceFee(performanceFee);

        increasePricePerShare(raise);
        generateUniV3Fees();
        distributeIchiFees();

        uint256 gain = ((adapter.convertToAssets(1e18) -
            adapter.highWaterMark()) * adapter.totalSupply()) / 1e18;
        uint256 fee = (gain * performanceFee) / 1e18;

        uint256 expectedFee = adapter.convertToShares(fee);

        vm.expectEmit(false, false, false, true, address(adapter));

        emit Harvested();

        adapter.harvest();

        // Multiply with the decimal offset
        assertApproxEqAbs(
            adapter.totalSupply(),
            defaultAmount * 1e9 + expectedFee,
            _delta_,
            "totalSupply"
        );
        assertApproxEqAbs(
            adapter.balanceOf(feeRecipient),
            expectedFee,
            _delta_,
            "expectedFee"
        );
    }

    function test__pause() public override {
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
            slippage,
            "totalAssets"
        );
        assertApproxEqAbs(
            oldTotalSupply,
            adapter.totalSupply(),
            slippage,
            "totalSupply"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(adapter)),
            oldTotalAssets,
            slippage,
            "asset balance"
        );
        assertApproxEqAbs(iouBalance(), 0, slippage, "iou balance");

        vm.startPrank(bob);
        // Deposit and mint are paused (maxDeposit/maxMint are set to 0 on pause)
        vm.expectRevert();
        adapter.deposit(defaultAmount, bob);

        vm.expectRevert();
        adapter.mint(defaultAmount, bob);

        // Withdraw and Redeem dont revert
        adapter.withdraw(defaultAmount / 10, bob, bob);
        adapter.redeem(defaultAmount / 10, bob, bob);
    }

    function test__unpause() public override {
        _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();
        uint256 oldIouBalance = iouBalance();

        adapter.pause();
        adapter.unpause();

        // We simply deposit back into the external protocol
        // TotalSupply and Assets dont change
        assertApproxEqAbs(
            oldTotalAssets,
            adapter.totalAssets(),
            slippage,
            "totalAssets"
        );
        assertApproxEqAbs(
            oldTotalSupply,
            adapter.totalSupply(),
            slippage,
            "totalSupply"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(adapter)),
            0,
            slippage,
            "asset balance"
        );
        assertApproxEqAbs(iouBalance(), oldIouBalance, slippage, "iou balance");

        // Deposit and mint dont revert
        vm.startPrank(bob);
        adapter.deposit(defaultAmount, bob);
        adapter.mint(defaultAmount * 1e9, bob);
    }
}
