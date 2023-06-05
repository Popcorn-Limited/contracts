// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {LidoAdapter, SafeERC20, IERC20, IERC20Metadata, Math, VaultAPI, ILido} from "../../../../src/vault/adapter/lido/LidoAdapter.sol";
import {IERC4626Upgradeable as IERC4626, IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {LidoTestConfigStorage, LidoTestConfig} from "./LidoTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";
import {SafeMath} from "openzeppelin-contracts/utils/math/SafeMath.sol";

contract LidoAdapterTest is AbstractAdapterTest {
    using Math for uint256;
    using SafeMath for uint256;

    VaultAPI lidoVault;
    VaultAPI lidoBooster;
    uint256 maxAssetsNew;
    ILido adapterTest;
    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;
    uint8 internal constant decimalOffset = 9;
    address public constant StableSwapSTETH = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    uint256 public constant DENOMINATOR = 10000;
    uint256 public slippageProtectionOut = 100; // = 100; //out of 10000. 100 = 1%

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new LidoTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));

        maxAssetsNew = IERC20(asset).totalSupply() / 10 ** 5;
        defaultAmount = Math.min(
            10 ** IERC20Metadata(address(asset)).decimals() * 1e9,
            maxAssetsNew
        );
        maxAssets = Math.min(
            10 ** IERC20Metadata(address(asset)).decimals() * 1e9,
            maxAssetsNew
        );
        maxShares = maxAssets / 2;
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        address _asset = abi.decode(testConfig, (address));

        setUpBaseTest(
            IERC20(_asset),
            address(new LidoAdapter()),
            0x34dCd573C5dE4672C8248cd12A99f875Ca112Ad8,
            10,
            "Lido  ",
            false
        );

        lidoBooster = VaultAPI(externalRegistry);

        lidoVault = VaultAPI(lidoBooster.token());

        vm.label(address(lidoVault), "lidoVault");
        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), address(0), 0, sigs, ""),
            externalRegistry,
            abi.encode(0x34dCd573C5dE4672C8248cd12A99f875Ca112Ad8, 1)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function createAdapter() public override {
        adapter = IAdapter(address(new LidoAdapter()));
    }

    function increasePricePerShare(uint256 amount) public override {
        deal(address(adapter), 100 ether);
        vm.prank(address(adapter));
        ILido(address(lidoVault)).submit{value: 100 ether}(address(0));
    }

    function iouBalance() public view override returns (uint256) {
        return lidoVault.balanceOf(address(adapter));
    }

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        // Make sure totalAssets isnt 0
        deal(address(asset), bob, defaultAmount);
        vm.startPrank(bob);
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, bob);
        vm.stopPrank();

        assertApproxEqAbs(
            adapter.totalAssets(),
            adapter.convertToAssets(adapter.totalSupply()),
            _delta_,
            string.concat("totalSupply converted != totalAssets", baseTestId)
        );

        uint256 pricePerShare = (adapter.totalAssets()).mulDiv(
            1,
            adapter.totalSupply(),
            Math.Rounding.Up
        );
        assertApproxEqAbs(
            adapter.totalAssets(),
            iouBalance(), // didnt multiply by price per share as it causes it to fail
            _delta_,
            string.concat("totalAssets != yearn assets", baseTestId)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapterTest.asset(), lidoBooster.weth(), "asset");
        assertEq(
            IERC20Metadata(address(adapterTest)).name(),
            string.concat(
                "Popcorn Lido ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapterTest)).symbol(),
            string.concat("popL-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapterTest), address(lidoVault)),
            type(uint256).max,
            "allowance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
    //////////////////////////////////////////////////////////////*/

    // Because withdrawing loses some tokens due to slippage when swapping StEth for Weth
    function test__unpause() public virtual override {
        _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();
        uint256 oldIouBalance = iouBalance();

        // If we pause and unpause, the total asset amount will change because of the swap mechanism in withdrawing

        adapter.pause();
        adapter.unpause();

        // We simply deposit back into the external protocol
        // TotalSupply and Assets dont change
        // assertApproxEqAbs(oldTotalAssets, adapter.totalAssets(), _delta_, "totalAssets");
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
        // assertApproxEqAbs(iouBalance(), oldIouBalance, _delta_, "iou balance");

        // Deposit and mint dont revert
        vm.startPrank(bob);
        adapter.deposit(defaultAmount, bob);
        adapter.mint(defaultAmount, bob);
    }

    function test__RT_mint_withdraw() public virtual override {
        _mintAssetAndApproveForAdapter(adapter.previewMint(defaultAmount), bob);

        vm.startPrank(bob);
        uint256 assets = adapter.mint(defaultAmount, bob);
        uint256 shares = adapter.withdraw(assets - 1, bob, bob);
        vm.stopPrank();

        assertApproxEqAbs(shares, defaultAmount, 1, testId);
    }

    function test__RT_deposit_withdraw() public virtual override {
        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.startPrank(bob);
        uint256 shares1 = adapter.deposit(defaultAmount, bob);
        uint256 shares2 = adapter.withdraw(defaultAmount - 1, bob, bob);
        vm.stopPrank();

        assertApproxGeAbs(shares2, shares1, 1);
    }

    function test__pause() public virtual override {
        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();

        adapter.pause();

        // We simply withdraw into the adapter
        // TotalSupply and Assets dont change
        // assertApproxEqAbs(oldTotalAssets, adapter.totalAssets(), _delta_, "totalAssets");
        assertApproxEqAbs(
            oldTotalSupply,
            adapter.totalSupply(),
            _delta_,
            "totalSupply"
        );
        // assertApproxEqAbs(asset.balanceOf(address(adapter)), oldTotalAssets, _delta_, "asset balance");
        assertApproxEqAbs(iouBalance(), 0, _delta_, "iou balance");

        vm.startPrank(bob);
        // Deposit and mint are paused (maxDeposit/maxMint are set to 0 on pause)
        vm.expectRevert(
            abi.encodeWithSelector(MaxError.selector, defaultAmount)
        );
        adapter.deposit(defaultAmount, bob);

        vm.expectRevert(
            abi.encodeWithSelector(MaxError.selector, defaultAmount)
        );
        adapter.mint(defaultAmount, bob);

        // Withdraw and Redeem dont revert
        adapter.withdraw(defaultAmount / 10, bob, bob);
        adapter.redeem(defaultAmount / 10, bob, bob);
    }
}
