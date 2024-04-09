// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {PendleAdapter, IPendleRouter, IPendleMarket, IPendleSYToken, Math, IERC20, IERC20Metadata} from "../../../../src/vault/adapter/pendle/PendleAdapter.sol";
import {PendleTestConfigStorage, PendleTestConfig} from "./PendleTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";
import "forge-std/console.sol";

contract PendleAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IPendleRouter pendleRouter = IPendleRouter(0x00000000005BBB0EF59571E58418F9a4357b68A0);
    
    IPendleSYToken synToken;
    address pendleMarket;
    address syToken = address(0xcbC72d92b2dc8187414F6734718563898740C0BC);
    address yieldToken = address(0xA53ad7E3A87546CCa450992d54d517c3C939c2BF);
    address principalToken = address(0xcf44E8402a99Db82d2AccCC4d9354657Be2121Db);

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new PendleTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _asset, address _market) = abi.decode(
            testConfig,
            (address, address)
        );

        pendleMarket = _market;
        (address _synToken, ,) = IPendleMarket(pendleMarket).readTokens();
        synToken = IPendleSYToken(_synToken);

        setUpBaseTest(
            IERC20(_asset),
            address(new PendleAdapter()),
            address(pendleRouter),
            10,
            "Pendle ",
            false
        );

        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), address(0), 0, sigs, ""),
            externalRegistry,
            abi.encode(pendleMarket)
        );

        defaultAmount = 10 ** IERC20Metadata(address(asset)).decimals();
        minFuzz = defaultAmount * 10_000;
        raise = defaultAmount * 100_000_000;
        maxAssets = defaultAmount * 1_000_000;
        maxShares = maxAssets / 2;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    // function increasePricePerShare(uint256 amount) public override {
    //     deal(
    //         address(asset),
    //         address(yearnVault),
    //         asset.balanceOf(address(yearnVault)) + amount
    //     );
    // }

    // function iouBalance() public view override returns (uint256) {
    //     return yearnVault.balanceOf(address(adapter));
    // }

    // Verify that totalAssets returns the expected amount
    // function verify_totalAssets() public override {
    //     // Make sure totalAssets isnt 0
    //     deal(address(asset), bob, defaultAmount);
    //     vm.startPrank(bob);
    //     asset.approve(address(adapter), defaultAmount);
    //     adapter.deposit(defaultAmount, bob);
    //     vm.stopPrank();

    //     assertApproxEqAbs(
    //         adapter.totalAssets(),
    //         adapter.convertToAssets(adapter.totalSupply()),
    //         _delta_,
    //         string.concat("totalSupply converted != totalAssets", baseTestId)
    //     );

    //     assertApproxEqAbs(
    //         adapter.totalAssets(),
    //         iouBalance().mulDiv(
    //             yearnVault.pricePerShare(),
    //             10 ** IERC20Metadata(address(asset)).decimals(),
    //              Math.Rounding.Ceil
    //         ),
    //         _delta_,
    //         string.concat("totalAssets != yearn assets", baseTestId)
    //     );
    // }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        createAdapter();

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            address(pendleRouter),
            abi.encode(pendleMarket)
        );

        assertEq(adapter.owner(), address(this), "owner");
        assertEq(adapter.strategy(), address(strategy), "strategy");
        assertEq(adapter.harvestCooldown(), 0, "harvestCooldown");
        assertEq(adapter.strategyConfig(), "", "strategyConfig");
        assertEq(
            IERC20Metadata(address(adapter)).decimals(),
            IERC20Metadata(address(asset)).decimals() + adapter.decimalOffset(),
            "decimals"
        );

        verify_adapterInit();
    }

    function test_depositWithdraw() public {
        uint256 amount = 1 ether;
        deal(adapter.asset(), bob, amount);

        vm.startPrank(bob);
        IERC20(adapter.asset()).approve(address(adapter), type(uint256).max);
        adapter.deposit(amount, bob);

        adapter.redeem(IERC20(address(adapter)).balanceOf(address(bob)), bob, bob);
        console.log(IERC20(adapter.asset()).balanceOf(bob));
        console.log(IERC20(adapter.asset()).balanceOf(address(adapter)));

        vm.stopPrank();
    }

    function verify_adapterInit() public override {
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Pendle ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vc-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(pendleRouter)),
            type(uint256).max,
            "allowance"
        );

        // Revert if asset is not compatible with pendle market
        address invalidAsset = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        createAdapter();
        vm.expectRevert();
        adapter.initialize(
            abi.encode(invalidAsset, address(this), strategy, 0, sigs, ""),
            address(pendleRouter),
            abi.encode(pendleMarket)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
    //////////////////////////////////////////////////////////////*/

    // NOTE - The yearn adapter suffers often from an off-by-one error which "steals" 1 wei from the user
    function test__RT_deposit_withdraw() public override {
        _mintAssetAndApproveForAdapter(minFuzz, bob);

        vm.startPrank(bob);
        uint256 shares1 = adapter.deposit(minFuzz, bob);
        uint256 shares2 = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
        vm.stopPrank();

        // We compare assets here with maxWithdraw since the shares of withdraw will always be lower than `compoundDefaultAmount`
        // This tests the same assumption though. As long as you can withdraw less or equal assets to the input amount you cant round trip
        assertGe(minFuzz, adapter.maxWithdraw(bob), testId);
    }

    // NOTE - The yearn adapter suffers often from an off-by-one error which "steals" 1 wei from the user
    function test__RT_mint_withdraw() public override {
        _mintAssetAndApproveForAdapter(adapter.previewMint(minFuzz), bob);

        vm.startPrank(bob);
        uint256 assets = adapter.mint(minFuzz, bob);
        uint256 shares = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
        vm.stopPrank();
        // We compare assets here with maxWithdraw since the shares of withdraw will always be lower than `compoundDefaultAmount`
        // This tests the same assumption though. As long as you can withdraw less or equal assets to the input amount you cant round trip
        assertGe(
            adapter.previewMint(minFuzz),
            adapter.maxWithdraw(bob),
            testId
        );
    }

    function test__RT_mint_redeem() public override {
        _mintAssetAndApproveForAdapter(adapter.previewMint(minFuzz), bob);

        vm.startPrank(bob);
        uint256 assets1 = adapter.mint(minFuzz, bob);
        uint256 assets2 = adapter.redeem(minFuzz, bob, bob);
        vm.stopPrank();

        assertLe(assets2, assets1, testId);
    }

    /*//////////////////////////////////////////////////////////////
                              PAUSE
    //////////////////////////////////////////////////////////////*/

    function test__unpause() public override {
        _mintAssetAndApproveForAdapter(minFuzz * 3, bob);

        vm.prank(bob);
        adapter.deposit(minFuzz, bob);

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
        adapter.deposit(minFuzz, bob);
        adapter.mint(minFuzz, bob);
    }
}
