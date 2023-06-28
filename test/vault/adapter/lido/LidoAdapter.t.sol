// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {LidoAdapter, SafeERC20, IERC20, Math, IERC20Metadata, ILido} from "../../../../src/vault/adapter/lido/LidoAdapter.sol";
import {LidoTestConfigStorage, LidoTestConfig} from "./LidoTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";
import {SafeMath} from "openzeppelin-contracts/utils/math/SafeMath.sol";
import {ICurveMetapool} from "../../../../src/interfaces/external/curve/ICurveMetapool.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

contract LidoAdapterTest is AbstractAdapterTest {
    using Math for uint256;
    using SafeMath for uint256;

    VaultAPI lidoVault;
    VaultAPI lidoBooster;
    uint256 maxAssetsNew;
    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;
    uint8 internal constant decimalOffset = 9;
    // ICurveMetapool public constant StableSwapSTETH =
    //     ICurveMetapool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    uint256 public constant DENOMINATOR = 10000;
    uint256 public slippageProtectionOut = 100; // = 100; //out of 10000. 100 = 1%

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new LidoTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _asset,) = abi.decode(testConfig, (address,uint256));

        setUpBaseTest(
            IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // Weth
            address(new LidoAdapter()),
            address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84), // stEth
            10,
            "Lido ",
            true
        );

        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );

        defaultAmount = 1 ether;
        raise = 100 ether;
        maxAssets = 10 ether;
        maxShares = 10e27;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function createAdapter() public override {
        adapter = IAdapter(Clones.clone(address(new LidoAdapter())));
        vm.label(address(adapter), "adapter");
    }

    function increasePricePerShare(uint256 amount) public override {
        deal(address(adapter), 100 ether);
        vm.prank(address(adapter));
        ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).submit{
            value: 100 ether
        }(address(0));
    }

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        _mintAsset(defaultAmount, bob);
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

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), lidoBooster.weth(), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "Popcorn Lido ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("popL-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(lidoVault)),
            type(uint256).max,
            "allowance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
    //////////////////////////////////////////////////////////////*/

    // Because withdrawing loses some tokens due to slippage when swapping StEth for Weth
    
    function test__unpause() public override {
        _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();
        uint256 oldIouBalance = iouBalance();
        uint256 dy = StableSwapSTETH.get_dy(STETHID, WETHID, oldTotalAssets);
        
        adapter.pause();
        adapter.unpause();

        // We simply deposit back into the external protocol
        // TotalSupply and Assets dont change
        assertApproxEqAbs(
            dy, // NOTE: oldTotalAssets doesn't take commission into account
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
            0,
            _delta_,
            "asset balance"
        );
        assertApproxEqAbs(iouBalance(), dy, _delta_, "iou balance"); // NOTE: oldTotalAssets doesn't take commission into account

        // Deposit and mint dont revert
        vm.startPrank(bob);
        adapter.deposit(defaultAmount, bob);
        adapter.mint(defaultAmount, bob);
    }

    function test__pause() public override {
        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();
        uint256 oldBalance = asset.balanceOf(address(adapter));
        uint256 dy = StableSwapSTETH.get_dy(STETHID, WETHID, oldTotalAssets);
        
        adapter.pause();

        // We simply withdraw into the adapter
        // TotalSupply and Assets dont change
        assertApproxEqAbs(
            dy, // NOTE: oldTotalAssets doesn't take commission into account
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
            dy, // NOTE: oldTotalAssets doesn't take commission into account
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
        adapter.withdraw(defaultAmount / 10, bob, bob);
        adapter.redeem(defaultAmount / 10, bob, bob);
    }
}
