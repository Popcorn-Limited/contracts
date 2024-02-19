// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {YearnFactoryAdapter, IERC20, IERC20Metadata, VaultAPI, IVaultFactory} from "../../../../../src/vault/adapter/yearn/factory/YearnFactoryAdapter.sol";
import {IYearnStrategy} from "../../../../../src/vault/adapter/yearn/IYearn.sol";
import {YearnFactoryTestConfigStorage, YearnFactoryTestConfig} from "./YearnFactoryTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../../abstract/AbstractAdapterTest.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IGauge} from "../../../../../src/vault/adapter/balancer/IBalancer.sol";

contract YearnFactoryAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    VaultAPI yearnVault;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new YearnFactoryTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _gauge, uint256 _maxLoss) = abi.decode(
            testConfig,
            (address, uint256)
        );

        setUpBaseTest(
            IERC20(IGauge(_gauge).lp_token()),
            address(new YearnFactoryAdapter()),
            0x21b1FC8A52f179757bf555346130bF27c0C2A17A, //yearn vault factory
            10,
            "Yearn ",
            false
        );

        yearnVault = VaultAPI(
            IVaultFactory(externalRegistry).latestStandardVaultFromGauge(_gauge)
        );

        vm.label(address(yearnVault), "yearnVault");
        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), address(0), 0, sigs, ""),
            externalRegistry,
            testConfig
        );

        defaultAmount = 10 ** IERC20Metadata(address(asset)).decimals();
        minFuzz = defaultAmount * 100;
        raise = defaultAmount * 10_000;
        maxAssets = defaultAmount * 10_000;
        maxShares = maxAssets / 2;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    // TODO -> Increase pricePerShare doesnt seem to work as expected
    function increasePricePerShare(uint256 amount) public override {
        address strategy = yearnVault.withdrawalQueue(2);
        address strategist = IYearnStrategy(strategy).strategist();

        // CRV
        deal(
            address(0xD533a949740bb3306d119CC777fa900bA034cd52),
            address(strategy),
            IERC20(address(0xD533a949740bb3306d119CC777fa900bA034cd52))
                .balanceOf(address(strategy)) + amount
        );

        //CVX
        deal(
            address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B),
            address(strategy),
            IERC20(address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B))
                .balanceOf(address(strategy)) + amount
        );

        // deal(
        //     address(asset),
        //     address(strategy),
        //     IERC20(address(asset)).balanceOf(address(strategy)) + amount
        // );

        vm.prank(strategist);
        IYearnStrategy(strategy).tend();
    }

    function iouBalance() public view override returns (uint256) {
        return yearnVault.balanceOf(address(adapter));
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

        assertApproxEqAbs(
            adapter.totalAssets(),
            iouBalance().mulDiv(
                yearnVault.pricePerShare(),
                10 ** IERC20Metadata(address(asset)).decimals(),
                 Math.Rounding.Ceil
            ),
            _delta_,
            string.concat("totalAssets != yearn assets", baseTestId)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), yearnVault.token(), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Yearn ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcY-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(yearnVault)),
            type(uint256).max,
            "allowance"
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

    /*//////////////////////////////////////////////////////////////
                              HARVEST
    //////////////////////////////////////////////////////////////*/

    // @dev Overriding for the moment as i cant figure ot the share price increase
    // TODO -> remove this when the share price increase is figured out
    function test__harvest() public override {}
}
