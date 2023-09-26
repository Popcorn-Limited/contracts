// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {IdleJuniorAdapter, SafeERC20, IERC20, IERC20Metadata, IStrategy, ERC20, IIdleCDO} from "../../../../../src/vault/adapter/idle/junior/IdleJuniorAdapter.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter, Math} from "../../abstract/AbstractAdapterTest.sol";
import {IdleTestConfigStorage, IdleTestConfig} from "../IdleTestConfigStorage.sol";
import {MockStrategyClaimer} from "../../../../utils/mocks/MockStrategyClaimer.sol";
import {IVaultController} from "../../../../../src/interfaces/vault/IVaultController.sol";

contract IdleJuniorAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    address registry = 0x84FDeE80F18957A041354E99C7eB407467D94d8E; // Registry
    IIdleCDO public cdo;
    address tranch;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new IdleTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        address _cdo = abi.decode(testConfig, (address));
        cdo = IIdleCDO(_cdo);
        address token = cdo.token();
        tranch = cdo.BBTranche();

        setUpBaseTest(
            IERC20(token),
            address(new IdleJuniorAdapter()),
            registry,
            10,
            "IDLE ",
            true
        );

        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );

        if (defaultAmount > adapter.maxDeposit(address(this))) {
            defaultAmount = adapter.maxDeposit(address(this)) / 1000;
        }
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function increasePricePerShare(uint256 amount) public override {
        deal(
            tranch,
            address(adapter),
            IERC20(tranch).balanceOf(address(adapter)) + amount
        );
    }

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        // Make sure totalAssets isnt 0
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

    /*//////////////////////////////////////////////////////////////
                            IMMUNIFY
    //////////////////////////////////////////////////////////////*/

    function logValues(
        IdleJuniorAdapter daiIdleJuniorAdapter,
        IERC20 tranche,
        IERC20 dai,
        string memory prefix
    ) internal {
        uint256 oldTotalAssets = daiIdleJuniorAdapter.totalAssets();
        uint256 oldTotalSupply = daiIdleJuniorAdapter.totalSupply();
        uint256 oldIouBalance = tranche.balanceOf(
            address(daiIdleJuniorAdapter)
        );
        uint256 oldAssetBalance = dai.balanceOf(address(daiIdleJuniorAdapter));

        emit log_named_uint(
            string.concat(prefix, "totalAssets"),
            oldTotalAssets
        );
        emit log_named_uint(
            string.concat(prefix, "totalSupply"),
            oldTotalSupply
        );
        emit log_named_uint(string.concat(prefix, "iouBalance"), oldIouBalance);
        emit log_named_uint(
            string.concat(prefix, "assetBalance"),
            oldAssetBalance
        );
    }

    function test__immunify() public {
        address daiWhale = 0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8;
        address attacker = address(31);

        IdleJuniorAdapter daiIdleJuniorAdapter = IdleJuniorAdapter(
            0x197F58De2559097d956b4192e8F89A2F36190a48
        );
        IERC20 dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        IERC20 tranche = IERC20(0x38D36353D07CfB92650822D9c31fB4AdA1c73D6E);
        address trancheWhale = 0x028AbC03CE5f8ed61174512F8635929CC5bb7116;

        // attacker has 1000 DAI
        vm.prank(daiWhale);
        dai.transfer(attacker, 1000 * 1e18);

        vm.startPrank(daiWhale);
        dai.approve(address(daiIdleJuniorAdapter), type(uint256).max);
        daiIdleJuniorAdapter.deposit(100_000 * 1e18, daiWhale); // 100k DAI deposited
        vm.stopPrank();

        emit log_named_uint(
            "Total supply of the adapter initially",
            daiIdleJuniorAdapter.totalSupply()
        );
        emit log_named_uint(
            "Total assets of adapter initially",
            daiIdleJuniorAdapter.totalAssets()
        );
        emit log_named_uint(
            "Idle DAI in the adapter initially",
            dai.balanceOf(address(daiIdleJuniorAdapter))
        ); // should be 0

        vm.roll(block.number + 1);

        // attacker redeems 1 share, start of the attack here
        vm.prank(daiWhale);
        daiIdleJuniorAdapter.redeem(1, daiWhale, daiWhale);

        emit log_named_uint(
            "Total supply of the adapter after redeeming 1 share",
            daiIdleJuniorAdapter.totalSupply()
        );
        emit log_named_uint(
            "Total assets of adapter after redeeming 1 share",
            daiIdleJuniorAdapter.totalAssets()
        ); // should be 1
        emit log_named_uint(
            "Idle DAI in the adapter after redeeming 1 share",
            dai.balanceOf(address(daiIdleJuniorAdapter))
        ); // should be all assets

        // Now, attacker deposits 1000 * 1e18 DAI
        vm.startPrank(attacker);
        dai.approve(address(daiIdleJuniorAdapter), type(uint256).max);
        daiIdleJuniorAdapter.deposit(1000e18, attacker);
        vm.stopPrank();

        vm.roll(block.number + 1);

        emit log_named_uint(
            "Total supply of the adapter after attackers deposit",
            daiIdleJuniorAdapter.totalSupply()
        );
        emit log_named_uint(
            "Total assets of adapter after attackers deposit",
            daiIdleJuniorAdapter.totalAssets()
        );
        emit log_named_uint(
            "Idle DAI in the adapter after attackers deposit",
            dai.balanceOf(address(daiIdleJuniorAdapter))
        ); // should be only attackers deposit

        // at this stage attacker has many more shares though it deposited the same amount of DAI
        emit log_named_uint(
            "Attackers shares",
            daiIdleJuniorAdapter.balanceOf(attacker)
        );
        emit log_named_uint(
            "Whales shares",
            daiIdleJuniorAdapter.balanceOf(daiWhale)
        ); // remember, whale depsoited 1M.

        address _owner = daiIdleJuniorAdapter.owner();

        // let owner airdrop 10 DAI to strategy as Popcorn team states
        vm.prank(trancheWhale);
        tranche.transfer(_owner, 10 * 1e18);
        vm.startPrank(_owner);
        tranche.transfer(address(daiIdleJuniorAdapter), 10 * 1e18);

        // pause-unpause, as Popcorn team states
        daiIdleJuniorAdapter.pause();
        daiIdleJuniorAdapter.unpause();

        emit log_named_uint(
            "Total supply of the adapter after pause-unpause",
            daiIdleJuniorAdapter.totalSupply()
        );
        emit log_named_uint(
            "Total assets of adapter after pause-unpause",
            daiIdleJuniorAdapter.totalAssets()
        ); // should be all assets
        emit log_named_uint(
            "Idle DAI in the adapter after pause-unpause",
            dai.balanceOf(address(daiIdleJuniorAdapter))
        ); // should be 0

        vm.stopPrank();

        // attacker withdraws, wil withdraw all DAI stealing 100k DAI
        vm.startPrank(attacker);
        emit log_named_uint(
            "Attackers shares",
            daiIdleJuniorAdapter.balanceOf(attacker)
        );
        daiIdleJuniorAdapter.approve(
            address(daiIdleJuniorAdapter),
            type(uint256).max
        );
        vm.roll(block.number + 1);
        uint whatsRedeemed = daiIdleJuniorAdapter.redeem(
            daiIdleJuniorAdapter.balanceOf(attacker),
            attacker,
            attacker
        );

        emit log_named_uint(
            "Total supply of the adapter after attack finish",
            daiIdleJuniorAdapter.totalSupply()
        );
        emit log_named_uint(
            "Total assets of adapter after attack finish",
            daiIdleJuniorAdapter.totalAssets()
        ); // should be 0
        emit log_named_uint(
            "Idle DAI in the adapter after attack finish",
            dai.balanceOf(address(daiIdleJuniorAdapter))
        ); // should be all assets
        emit log_named_uint("Whats redeemed by the attacker", whatsRedeemed); // should be all assets

        // attacker deposited 1000 DAI and stole 100k DAI.
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        createAdapter();
        uint256 callTime = block.timestamp;

        vm.expectEmit(false, false, false, true, address(adapter));
        emit Initialized(uint8(1));
        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfigStorage.getTestConfig(0)
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

    function verify_adapterInit() public override {
        // assertNotEq(IEllipsisLpStaking(lpStaking).depositTokens(adapter.asset()), address(0), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Idle Junior ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcIdlJ-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );
    }

    function test__previewWithdraw(uint8 fuzzAmount) public override {
        uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

        uint256 reqAssets = adapter.previewMint(
            adapter.previewWithdraw(amount)
        ) * 10;
        _mintAssetAndApproveForAdapter(reqAssets, bob);
        vm.prank(bob);
        adapter.deposit(reqAssets, bob);

        vm.roll(block.number + 1);

        prop_previewWithdraw(bob, bob, bob, amount, testId);
    }

    function test__previewRedeem(uint8 fuzzAmount) public override {
        uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);

        uint256 reqAssets = adapter.previewMint(amount) * 10;
        _mintAssetAndApproveForAdapter(reqAssets, bob);
        vm.prank(bob);
        adapter.deposit(reqAssets, bob);

        vm.roll(block.number + 1);

        prop_previewRedeem(bob, bob, bob, amount, testId);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/MINT/WITHDRAW/REDEEM
  //////////////////////////////////////////////////////////////*/

    function test__withdraw(uint8 fuzzAmount) public override {
        uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

            uint256 reqAssets = adapter.previewMint(
                adapter.previewWithdraw(amount)
            ) * 10;
            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);

            adapter.deposit(reqAssets, bob);
            vm.roll(block.number + 1);

            prop_withdraw(bob, bob, amount / 10, testId);

            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);

            adapter.deposit(reqAssets, bob);
            vm.roll(block.number + 1);

            increasePricePerShare(raise);

            vm.prank(bob);
            adapter.approve(alice, type(uint256).max);

            prop_withdraw(alice, bob, amount, testId);
        }
    }

    function test__redeem(uint8 fuzzAmount) public override {
        uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

            uint256 reqAssets = adapter.previewMint(amount) * 10;
            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);

            adapter.deposit(reqAssets, bob);
            vm.roll(block.number + 1);

            prop_redeem(bob, bob, amount, testId);

            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);

            adapter.deposit(reqAssets, bob);
            vm.roll(block.number + 1);

            increasePricePerShare(raise);

            vm.prank(bob);
            adapter.approve(alice, type(uint256).max);
            prop_redeem(alice, bob, amount, testId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
  //////////////////////////////////////////////////////////////*/

    function test__RT_deposit_redeem() public override {
        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.startPrank(bob);
        uint256 shares = adapter.deposit(defaultAmount, bob);

        vm.roll(block.number + 1);

        uint256 assets = adapter.redeem(adapter.maxRedeem(bob), bob, bob);
        vm.stopPrank();

        // Pass the test if maxRedeem is smaller than deposit since round trips are impossible
        if (adapter.maxRedeem(bob) == defaultAmount) {
            assertLe(assets, defaultAmount, testId);
        }
    }

    function test__RT_deposit_withdraw() public override {
        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.startPrank(bob);
        uint256 shares1 = adapter.deposit(defaultAmount, bob);

        vm.roll(block.number + 1);

        uint256 shares2 = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
        vm.stopPrank();

        // Pass the test if maxWithdraw is smaller than deposit since round trips are impossible
        if (adapter.maxWithdraw(bob) == defaultAmount) {
            assertGe(shares2, shares1, testId);
        }
    }

    function test__RT_mint_withdraw() public override {
        _mintAssetAndApproveForAdapter(adapter.previewMint(defaultAmount), bob);

        vm.startPrank(bob);
        uint256 assets = adapter.mint(defaultAmount, bob);

        vm.roll(block.number + 1);

        uint256 shares = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
        vm.stopPrank();

        if (adapter.maxWithdraw(bob) == assets) {
            assertGe(shares, defaultAmount, testId);
        }
    }

    function test__RT_mint_redeem() public override {
        _mintAssetAndApproveForAdapter(adapter.previewMint(defaultAmount), bob);

        vm.startPrank(bob);
        uint256 assets1 = adapter.mint(defaultAmount, bob);

        vm.roll(block.number + 1);

        uint256 assets2 = adapter.redeem(adapter.maxRedeem(bob), bob, bob);
        vm.stopPrank();

        if (adapter.maxRedeem(bob) == defaultAmount) {
            assertLe(assets2, assets1, testId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          MAX VIEWS
    //////////////////////////////////////////////////////////////*/

    // NOTE: These Are just prop tests currently. Override tests here if the adapter has unique max-functions which override AdapterBase.sol

    function test__maxDeposit() public override {
        prop_maxDeposit(bob);

        // Deposit smth so withdraw on pause is not 0
        _mintAsset(defaultAmount, address(this));
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, address(this));

        vm.roll(block.number + 1);
        adapter.pause();
        assertEq(adapter.maxDeposit(bob), 0);
    }

    function test__maxMint() public override {
        prop_maxMint(bob);

        // Deposit smth so withdraw on pause is not 0
        _mintAsset(defaultAmount, address(this));
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, address(this));

        vm.roll(block.number + 1);

        adapter.pause();
        assertEq(adapter.maxMint(bob), 0);
    }

    /*//////////////////////////////////////////////////////////////
                              PAUSE
    //////////////////////////////////////////////////////////////*/

    function test__pause() public override {
        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();

        vm.roll(block.number + 1);
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

        vm.roll(block.number + 1);
        adapter.pause();

        vm.roll(block.number + 1);
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
        adapter.deposit(defaultAmount, bob);
        adapter.mint(defaultAmount, bob);
    }
}
