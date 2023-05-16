// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../utils/mocks/MockERC20.sol";
import {MockERC4626} from "../utils/mocks/MockERC4626.sol";
import {MultiStrategyVault, AdapterConfig, VaultFees} from "../../src/vault/MultiStrategyVault.sol";
import {IERC4626Upgradeable as IERC4626, IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import "forge-std/console.sol";

contract MultiStrategyVaultTester is Test {
    using FixedPointMathLib for uint256;

    bytes32 constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    MockERC20 asset;
    AdapterConfig[10] adapters;
    MultiStrategyVault multiStrategyVault;

    address adapterImplementation;
    address implementation;

    uint256 constant SECONDS_PER_YEAR = 365.25 days;

    address feeRecipient = address(0x4444);
    address alice = address(0xABCD);
    address bob = address(0xDCBA);

    event NewFeesProposed(VaultFees newFees, uint256 timestamp);
    event ChangedFees(VaultFees oldFees, VaultFees newFees);
    event FeeRecipientUpdated(address oldFeeRecipient, address newFeeRecipient);
    event NewAdaptersProposed(
        AdapterConfig[10] newAdapter,
        uint8 adapterCount,
        uint256 timestamp
    );
    event ChangedAdapters(
        AdapterConfig[10] oldAdapter,
        uint8 oldAdapterCount,
        AdapterConfig[10] newAdapter,
        uint8 newAdapterCount
    );
    event QuitPeriodSet(uint256 quitPeriod);
    event Paused(address account);
    event Unpaused(address account);
    event DepositLimitSet(uint256 depositLimit);

    function setUp() public {
        vm.label(feeRecipient, "feeRecipient");
        vm.label(alice, "alice");
        vm.label(bob, "bob");

        asset = new MockERC20("Mock Token", "TKN", 18);

        adapterImplementation = address(new MockERC4626());
        implementation = address(new MultiStrategyVault());

        adapters[0].adapter = _createAdapter(IERC20(address(asset)));
        adapters[1].adapter = _createAdapter(IERC20(address(asset)));
        adapters[2].adapter = _createAdapter(IERC20(address(asset)));

        adapters[0].allocation = 0.25e18;
        adapters[1].allocation = 0.25e18;
        adapters[2].allocation = 0.5e18;

        multiStrategyVault = MultiStrategyVault(Clones.clone(implementation));

        multiStrategyVault.initialize(
            IERC20(address(asset)),
            adapters,
            3,
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            feeRecipient,
            type(uint256).max,
            address(this)
        );
    }

    function _setFees(
        uint64 depositFee,
        uint64 withdrawalFee,
        uint64 managementFee,
        uint64 performanceFee
    ) internal {
        multiStrategyVault.proposeFees(
            VaultFees({
                deposit: depositFee,
                withdrawal: withdrawalFee,
                management: managementFee,
                performance: performanceFee
            })
        );

        vm.warp(block.timestamp + 3 days);
        multiStrategyVault.changeFees();
    }

    function _createAdapter(IERC20 _asset) internal returns (MockERC4626) {
        address adapterAddress = Clones.clone(adapterImplementation);
        MockERC4626(adapterAddress).initialize(
            _asset,
            "Mock Token Vault",
            "vwTKN"
        );
        return MockERC4626(adapterAddress);
    }

    // @audit when you change the allocation midway, you'll break subsequent withdrawals

    function test__full_simulation(
        uint depositAmount,
        uint mintAmount,
        uint withdrawAmount,
        uint redeemAmount,
        uint adapterYield
    ) public {
        // Goal is to have a test that simulates the whole thing:
        // - two users
        // - one mints the other deposits
        // - one redeems the other withdraws
        // - vault and adapter both take fees
        // - the adapter earn yield
        vm.assume(depositAmount > 0 && depositAmount <= 1000e18);
        vm.assume(mintAmount >= 1e9 && mintAmount <= 1000e27);
        vm.assume(adapterYield <= 1000e18);
        vm.assume(withdrawAmount > 0 && withdrawAmount <= depositAmount);
        vm.assume(redeemAmount > 1e9 && redeemAmount <= mintAmount);
    
        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(multiStrategyVault), depositAmount);
        multiStrategyVault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint bobAssetAmount = multiStrategyVault.previewMint(mintAmount);
        asset.mint(bob, bobAssetAmount);
        vm.startPrank(bob);
        asset.approve(address(multiStrategyVault), bobAssetAmount);
        multiStrategyVault.mint(mintAmount, bob);
        vm.stopPrank();
        
        assertApproxEqAbs(multiStrategyVault.totalAssets(), depositAmount + bobAssetAmount, 1, "totalAssets doesn't match deposit amount");
        
        // one of the adapters earns yield that will be paid out to Alice and Bob when they redeem
        // their shares.
        asset.mint(address(adapters[2].adapter), adapterYield);

        vm.prank(alice);
        multiStrategyVault.withdraw(withdrawAmount, alice, alice);

        vm.prank(bob);
        multiStrategyVault.redeem(redeemAmount, bob, bob);
    }

    function test__metadata() public {
        address strategyVault = Clones.clone(implementation);
        MultiStrategyVault newMultiStrategyVault = MultiStrategyVault(
            strategyVault
        );

        uint256 callTime = block.timestamp;
        newMultiStrategyVault.initialize(
            IERC20(address(asset)),
            adapters,
            3,
            VaultFees({
                deposit: 100,
                withdrawal: 100,
                management: 100,
                performance: 100
            }),
            feeRecipient,
            type(uint256).max,
            bob
        );

        assertEq(newMultiStrategyVault.name(), "Popcorn Mock Token Vault");
        assertEq(newMultiStrategyVault.symbol(), "pop-TKN");
        assertEq(newMultiStrategyVault.decimals(), 27);

        assertEq(address(newMultiStrategyVault.asset()), address(asset));
        assertEq(newMultiStrategyVault.owner(), bob);

        (IERC4626 nAdapter0, ) = newMultiStrategyVault.adapters(0);
        (IERC4626 nAdapter1, ) = newMultiStrategyVault.adapters(1);
        (IERC4626 nAdapter2, ) = newMultiStrategyVault.adapters(2);
        assertEq(address(adapters[0].adapter), address(nAdapter0));
        assertEq(address(adapters[1].adapter), address(nAdapter1));
        assertEq(address(adapters[2].adapter), address(nAdapter2));

        (
            uint256 deposit,
            uint256 withdrawal,
            uint256 management,
            uint256 performance
        ) = newMultiStrategyVault.fees();
        assertEq(deposit, 100);
        assertEq(withdrawal, 100);
        assertEq(management, 100);
        assertEq(performance, 100);
        assertEq(newMultiStrategyVault.feeRecipient(), feeRecipient);
        assertEq(newMultiStrategyVault.highWaterMark(), 1e9);
        assertEq(newMultiStrategyVault.feesUpdatedAt(), callTime);

        assertEq(newMultiStrategyVault.quitPeriod(), 3 days);
        assertEq(
            asset.allowance(address(newMultiStrategyVault), address(nAdapter0)),
            type(uint256).max
        );
        assertEq(
            asset.allowance(address(newMultiStrategyVault), address(nAdapter1)),
            type(uint256).max
        );
        assertEq(
            asset.allowance(address(newMultiStrategyVault), address(nAdapter2)),
            type(uint256).max
        );
    }

    function testFail__initialize_asset_is_zero() public {
        address newStrategyVaultAddress = address(new MultiStrategyVault());
        vm.label(newStrategyVaultAddress, "vault");

        multiStrategyVault = MultiStrategyVault(newStrategyVaultAddress);
        multiStrategyVault.initialize(
            IERC20(address(0)),
            adapters,
            3,
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            feeRecipient,
            type(uint256).max,
            address(this)
        );
    }

    function testFail__initialize_adapter_asset_is_not_matching() public {
        MockERC20 newAsset = new MockERC20("New Mock Token", "NTKN", 18);
        AdapterConfig[10] memory newAdapters;
        newAdapters[0].adapter = _createAdapter(IERC20(address(newAsset)));
        newAdapters[1].adapter = _createAdapter(IERC20(address(newAsset)));
        newAdapters[2].adapter = _createAdapter(IERC20(address(newAsset)));
        newAdapters[3].adapter = _createAdapter(IERC20(address(newAsset)));

        newAdapters[0].allocation = 0.1e18;
        newAdapters[1].allocation = 0.2e18;
        newAdapters[2].allocation = 0.3e18;
        newAdapters[3].allocation = 0.4e18;
        address newStrategyVaultAddress = address(new MultiStrategyVault());

        multiStrategyVault = MultiStrategyVault(newStrategyVaultAddress);
        multiStrategyVault.initialize(
            IERC20(address(asset)),
            newAdapters,
            4,
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            feeRecipient,
            type(uint256).max,
            address(this)
        );
    }

    function testFail__initialize_adapter_addressZero() public {
        AdapterConfig[10] memory newAdapters;
        newAdapters[0].adapter = _createAdapter(IERC20(address(0)));
        newAdapters[1].adapter = _createAdapter(IERC20(address(0)));
        newAdapters[2].adapter = _createAdapter(IERC20(address(0)));
        newAdapters[3].adapter = _createAdapter(IERC20(address(0)));

        newAdapters[0].allocation = 0.1e18;
        newAdapters[1].allocation = 0.2e18;
        newAdapters[2].allocation = 0.3e18;
        newAdapters[3].allocation = 0.4e18;
        address newStrategyVaultAddress = address(new MultiStrategyVault());

        multiStrategyVault = MultiStrategyVault(newStrategyVaultAddress);
        multiStrategyVault.initialize(
            IERC20(address(asset)),
            newAdapters,
            4,
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            feeRecipient,
            type(uint256).max,
            address(this)
        );
    }

    function testFail__initialize_fees_too_high() public {
        address newStrategyVaultAddress = address(new MultiStrategyVault());

        multiStrategyVault = MultiStrategyVault(newStrategyVaultAddress);
        multiStrategyVault.initialize(
            IERC20(address(asset)),
            adapters,
            3,
            VaultFees({
                deposit: 1e18,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            feeRecipient,
            type(uint256).max,
            address(this)
        );
    }

    function testFail__initialize_feeRecipient_addressZero() public {
        address newStrategyVaultAddress = address(new MultiStrategyVault());

        multiStrategyVault = MultiStrategyVault(newStrategyVaultAddress);
        multiStrategyVault.initialize(
            IERC20(address(asset)),
            adapters,
            3,
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            address(0),
            type(uint256).max,
            address(this)
        );
    }

    function test__deposit_withdraw(uint128 amount) public {
        amount = uint128(bound(uint256(amount), 100, 1 ether));

        uint256 aliceassetAmount = amount;

        asset.mint(alice, aliceassetAmount);

        vm.prank(alice);
        asset.approve(address(multiStrategyVault), aliceassetAmount);
        assertEq(
            asset.allowance(alice, address(multiStrategyVault)),
            aliceassetAmount
        );

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceShareAmount = multiStrategyVault.deposit(
            aliceassetAmount,
            alice
        );

        // assertEq(adapter.afterDepositHookCalledCounter(), 1);

        // Expect exchange rate to be 1:1e9 on initial deposit.
        assertEq(aliceassetAmount * 1e9, aliceShareAmount);
        assertEq(
            multiStrategyVault.previewWithdraw(aliceassetAmount),
            aliceShareAmount
        );
        assertEq(
            multiStrategyVault.previewDeposit(aliceassetAmount),
            aliceShareAmount
        );
        assertEq(multiStrategyVault.totalSupply(), aliceShareAmount);
        assertEq(multiStrategyVault.totalAssets(), aliceassetAmount);
        assertEq(multiStrategyVault.balanceOf(alice), aliceShareAmount);
        assertEq(
            multiStrategyVault.convertToAssets(
                multiStrategyVault.balanceOf(alice)
            ),
            aliceassetAmount
        );
        assertEq(asset.balanceOf(alice), alicePreDepositBal - aliceassetAmount);
        
        vm.prank(alice);
        multiStrategyVault.withdraw(aliceassetAmount, alice, alice);

        // assertEq(adapter.beforeWithdrawHookCalledCounter(), 1);
        assertEq(multiStrategyVault.totalAssets(), 0);
        assertEq(multiStrategyVault.balanceOf(alice), 0);
        assertEq(
            multiStrategyVault.convertToAssets(
                multiStrategyVault.balanceOf(alice)
            ),
            0
        );
        assertEq(asset.balanceOf(alice), alicePreDepositBal);
    }

    function testFail__deposit_zero() public {
        multiStrategyVault.deposit(0, address(this));
    }

    function testFail__withdraw_zero() public {
        multiStrategyVault.withdraw(0, address(this), address(this));
    }

    function testFail__deposit_with_no_approval() public {
        multiStrategyVault.deposit(1e18, address(this));
    }

    function testFail__deposit_with_not_enough_approval() public {
        asset.mint(address(this), 1e18);
        asset.approve(address(multiStrategyVault), 0.5e18);
        assertEq(
            asset.allowance(address(this), address(multiStrategyVault)),
            0.5e18
        );

        multiStrategyVault.deposit(1e18, address(this));
    }

    function testFail__withdraw_with_not_enough_assets() public {
        asset.mint(address(this), 0.5e18);
        asset.approve(address(multiStrategyVault), 0.5e18);

        multiStrategyVault.deposit(0.5e18, address(this));

        multiStrategyVault.withdraw(1e18, address(this), address(this));
    }

    function testFail__withdraw_with_no_assets() public {
        multiStrategyVault.withdraw(1e18, address(this), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          MINT / REDEEM
    //////////////////////////////////////////////////////////////*/

    function test__mint_redeem(uint128 amount) public {
        // 1e9 shares = 1 underlying token.
        vm.assume(amount >= 1e12);

        uint256 aliceShareAmount = amount;
        asset.mint(alice, aliceShareAmount);

        vm.prank(alice);
        asset.approve(address(multiStrategyVault), aliceShareAmount);
        assertEq(
            asset.allowance(alice, address(multiStrategyVault)),
            aliceShareAmount
        );

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceAssetAmount = multiStrategyVault.mint(
            aliceShareAmount,
            alice
        );

        // assertEq(adapter.afterDepositHookCalledCounter(), 1);

        // Expect exchange rate to be 1e9:1 on initial mint.
        // We allow 1e9 delta since virtual shares lead to amounts between 1e9 to demand/mint more shares
        // E.g. (1e9 + 1) to 2e9 assets requires 2e9 shares to withdraw
        assertApproxEqAbs(
            aliceShareAmount / 1e9,
            aliceAssetAmount,
            1e9,
            "share = assets"
        );
        assertApproxEqAbs(
            multiStrategyVault.previewWithdraw(aliceAssetAmount),
            aliceShareAmount,
            1e9,
            "pw"
        );
        assertApproxEqAbs(
            multiStrategyVault.previewDeposit(aliceAssetAmount),
            aliceShareAmount,
            1e9,
            "pd"
        );
        assertEq(multiStrategyVault.totalSupply(), aliceShareAmount, "ts");
        // rounding can cause the totalAssets to be lower than the deposited amount.
        // Shouldn't be an issue after the first deposit 
        assertApproxEqAbs(multiStrategyVault.totalAssets(), aliceAssetAmount, 1, "ta");
        assertEq(multiStrategyVault.balanceOf(alice), aliceShareAmount, "bal");
        assertApproxEqAbs(
            multiStrategyVault.convertToAssets(
                multiStrategyVault.balanceOf(alice)
            ),
            aliceAssetAmount,
            1e9,
            "convert"
        );
        assertEq(
            asset.balanceOf(alice),
            alicePreDepositBal - aliceAssetAmount,
            "a bal"
        );
        
        vm.prank(alice);
        multiStrategyVault.redeem(aliceShareAmount, alice, alice);

        // assertEq(adapter.beforeWithdrawHookCalledCounter(), 1);

        assertEq(multiStrategyVault.totalAssets(), 0);
        assertEq(multiStrategyVault.balanceOf(alice), 0);
        assertEq(
            multiStrategyVault.convertToAssets(
                multiStrategyVault.balanceOf(alice)
            ),
            0
        );
        assertApproxEqAbs(asset.balanceOf(alice), alicePreDepositBal, 1);
    }

    function testFail__mint_zero() public {
        multiStrategyVault.mint(0, address(this));
    }

    function testFail__redeem_zero() public {
        multiStrategyVault.redeem(0, address(this), address(this));
    }

    function testFail__mint_with_no_approval() public {
        multiStrategyVault.mint(1e18, address(this));
    }

    function testFail__mint_with_not_enough_approval() public {
        asset.mint(address(this), 1e18);
        asset.approve(address(multiStrategyVault), 1e6);
        assertEq(
            asset.allowance(address(this), address(multiStrategyVault)),
            1e6
        );

        multiStrategyVault.mint(1e18, address(this));
    }

    function testFail__redeem_with_not_enough_shares() public {
        asset.mint(address(this), 0.5e18);
        asset.approve(address(multiStrategyVault), 0.5e18);

        multiStrategyVault.deposit(0.5e18, address(this));

        multiStrategyVault.redeem(1e27, address(this), address(this));
    }

    function testFail__redeem_with_no_shares() public {
        multiStrategyVault.redeem(1e18, address(this), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                DEPOSIT / MINT / WITHDRAW / REDEEM
    //////////////////////////////////////////////////////////////*/

    function test__interactions_for_someone_else() public {
        // init 2 users with a 1e18 balance
        asset.mint(alice, 1e18);
        asset.mint(bob, 1e18);

        vm.prank(alice);
        asset.approve(address(multiStrategyVault), 1e18);

        vm.prank(bob);
        asset.approve(address(multiStrategyVault), 1e18);

        // alice deposits 1e18 for bob
        vm.prank(alice);
        multiStrategyVault.deposit(1e18, bob);

        assertEq(multiStrategyVault.balanceOf(alice), 0);
        assertEq(multiStrategyVault.balanceOf(bob), 1e27);
        assertEq(asset.balanceOf(alice), 0);

        // bob mint 1e27 for alice
        vm.prank(bob);
        multiStrategyVault.mint(1e27, alice);
        assertEq(multiStrategyVault.balanceOf(alice), 1e27);
        assertEq(multiStrategyVault.balanceOf(bob), 1e27);
        assertEq(asset.balanceOf(bob), 0);

        // alice redeem 1e27 for bob
        vm.prank(alice);
        multiStrategyVault.redeem(1e27, bob, alice);

        assertEq(multiStrategyVault.balanceOf(alice), 0);
        assertEq(multiStrategyVault.balanceOf(bob), 1e27);
        assertEq(asset.balanceOf(bob), 1e18);

        // bob withdraw 1e27 for alice
        vm.prank(bob);
        multiStrategyVault.withdraw(1e18, alice, bob);

        assertEq(multiStrategyVault.balanceOf(alice), 0);
        assertEq(multiStrategyVault.balanceOf(bob), 0);
        assertEq(asset.balanceOf(alice), 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                          TAKING FEES
    //////////////////////////////////////////////////////////////*/

    function test__previewDeposit_previewMint_takes_fees_into_account(
        uint8 fuzzAmount
    ) public {
        uint256 amount = bound(uint256(fuzzAmount), 100, 1 ether);

        _setFees(1e17, 0, 0, 0);

        asset.mint(alice, amount);

        vm.prank(alice);
        asset.approve(address(multiStrategyVault), amount);

        // Test PreviewDeposit and Deposit
        uint256 expectedShares = multiStrategyVault.previewDeposit(amount);

        vm.prank(alice);
        uint256 actualShares = multiStrategyVault.deposit(amount, alice);
        assertApproxEqAbs(expectedShares, actualShares, 2);
    }

    function test__previewWithdraw_previewRedeem_takes_fees_into_account(
        uint8 fuzzAmount
    ) public {
        uint256 amount = bound(uint256(fuzzAmount), 10000, 1 ether);
        emit log_named_uint("Amount", amount);
        _setFees(0, 1e17, 0, 0);

        asset.mint(alice, amount);
        asset.mint(bob, amount);

        vm.startPrank(alice);
        asset.approve(address(multiStrategyVault), amount);
        uint256 shares = multiStrategyVault.deposit(amount, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        asset.approve(address(multiStrategyVault), amount);
        multiStrategyVault.deposit(amount, bob);
        vm.stopPrank();

        // Test PreviewWithdraw and Withdraw
        // NOTE: Reduce the amount of assets to withdraw to take withdrawalFee into account (otherwise we would withdraw more than we deposited)
        uint256 withdrawAmount = (amount / 10) * 9;
        uint256 expectedShares = multiStrategyVault.previewWithdraw(
            withdrawAmount
        );
        emit log_named_uint("Withdraw Amount", withdrawAmount);
        emit log_named_uint("Expected Shares", expectedShares);

        vm.prank(alice);
        uint256 actualShares = multiStrategyVault.withdraw(
            withdrawAmount,
            alice,
            alice
        );
        assertApproxEqAbs(expectedShares, actualShares, 1);

        // Test PreviewRedeem and Redeem
        uint256 expectedAssets = multiStrategyVault.previewRedeem(shares);

        vm.prank(bob);
        uint256 actualAssets = multiStrategyVault.redeem(shares, bob, bob);
        assertApproxEqAbs(expectedAssets, actualAssets, 1);
    }

    function test__managementFee(uint128 timeframe) public {
        // Test Timeframe less than 10 years
        timeframe = uint128(bound(timeframe, 1, 315576000));
        uint256 depositAmount = 1 ether;

        _setFees(0, 0, 1e17, 0);

        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(multiStrategyVault), depositAmount);
        multiStrategyVault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Increase Block Time to trigger managementFee
        vm.warp(block.timestamp + timeframe);

        uint256 expectedFeeInAsset = multiStrategyVault.accruedManagementFee();

        uint256 supply = multiStrategyVault.totalSupply();
        uint256 expectedFeeInShares = supply == 0
            ? expectedFeeInAsset
            : expectedFeeInAsset.mulDivDown(
                supply,
                1 ether - expectedFeeInAsset
            );

        multiStrategyVault.takeManagementAndPerformanceFees();

        assertEq(
            multiStrategyVault.totalSupply(),
            (depositAmount * 1e9) + expectedFeeInShares,
            "ts"
        );
        assertEq(
            multiStrategyVault.balanceOf(feeRecipient),
            expectedFeeInShares,
            "fee bal"
        );
        assertApproxEqAbs(
            multiStrategyVault.convertToAssets(expectedFeeInShares),
            expectedFeeInAsset,
            10,
            "convert back"
        );

        // High Water Mark should remain unchanged
        assertEq(multiStrategyVault.highWaterMark(), 1e9, "hwm");
    }

    function test__managementFee_change_fees_later() public {
        uint256 depositAmount = 1 ether;

        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(multiStrategyVault), depositAmount);
        multiStrategyVault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Set it to half the time without any fees
        vm.warp(block.timestamp + (SECONDS_PER_YEAR / 2));
        assertEq(multiStrategyVault.accruedManagementFee(), 0);

        _setFees(0, 0, 1e17, 0);

        vm.warp(block.timestamp + (SECONDS_PER_YEAR / 2));

        assertEq(
            multiStrategyVault.accruedManagementFee(),
            ((1 ether * 1e17) / 1e18) / 2
        );
    }

    function test__performanceFee(uint128 amount) public {
        vm.assume(amount >= 1e18);
        uint256 depositAmount = 1 ether;

        _setFees(0, 0, 0, 1e17);

        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(multiStrategyVault), depositAmount);
        multiStrategyVault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Increase asset assets to trigger performanceFee
        asset.mint(
            address(adapters[0].adapter),
            uint256(amount).mulDivDown(adapters[0].allocation, 1e18)
        );
        asset.mint(
            address(adapters[1].adapter),
            uint256(amount).mulDivDown(adapters[1].allocation, 1e18)
        );
        asset.mint(
            address(adapters[2].adapter),
            uint256(amount).mulDivDown(adapters[2].allocation, 1e18)
        );

        uint256 expectedFeeInAsset = multiStrategyVault.accruedPerformanceFee();

        uint256 supply = multiStrategyVault.totalSupply();
        uint256 totalAssets = multiStrategyVault.totalAssets();

        uint256 expectedFeeInShares = supply == 0
            ? expectedFeeInAsset
            : expectedFeeInAsset.mulDivDown(
                supply,
                totalAssets - expectedFeeInAsset
            );

        multiStrategyVault.takeManagementAndPerformanceFees();

        assertEq(
            multiStrategyVault.totalSupply(),
            (depositAmount * 1e9) + expectedFeeInShares,
            "ts"
        );
        assertEq(
            multiStrategyVault.balanceOf(feeRecipient),
            expectedFeeInShares,
            "bal"
        );

        // There should be a new High Water Mark
        assertApproxEqRel(
            multiStrategyVault.highWaterMark(),
            totalAssets / 1e9,
            30,
            "hwm"
        );
    }

    function test_performanceFee2() public {
        asset = new MockERC20("Mock Token", "TKN", 6);
        adapters[0].adapter = _createAdapter(IERC20(address(asset)));
        adapters[1].adapter = _createAdapter(IERC20(address(asset)));
        adapters[2].adapter = _createAdapter(IERC20(address(asset)));
        address vaultAddress = Clones.clone(implementation);
        multiStrategyVault = MultiStrategyVault(vaultAddress);
        vm.label(vaultAddress, "vault");
        multiStrategyVault.initialize(
            IERC20(address(asset)),
            adapters,
            3,
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 1e17
            }),
            feeRecipient,
            type(uint256).max,
            address(this)
        );

        uint256 depositAmount = 1e6;
        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(multiStrategyVault), depositAmount);
        multiStrategyVault.deposit(depositAmount, alice);
        vm.stopPrank();

        asset.mint(
            address(adapters[0].adapter),
            uint256(1e6).mulDivDown(adapters[0].allocation, 1e18)
        );
        asset.mint(
            address(adapters[1].adapter),
            uint256(1e6).mulDivDown(adapters[1].allocation, 1e18)
        );
        asset.mint(
            address(adapters[2].adapter),
            uint256(1e6).mulDivDown(adapters[2].allocation, 1e18)
        );

        // Take 10% of 1e6
        assertEq(multiStrategyVault.accruedPerformanceFee(), 1e5 - 1);
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE FEES
    //////////////////////////////////////////////////////////////*/

    // Propose Fees
    function test__proposeFees() public {
        VaultFees memory newVaultFees = VaultFees({
            deposit: 1,
            withdrawal: 1,
            management: 1,
            performance: 1
        });

        uint256 callTime = block.timestamp;
        vm.expectEmit(false, false, false, true, address(multiStrategyVault));
        emit NewFeesProposed(newVaultFees, callTime);

        multiStrategyVault.proposeFees(newVaultFees);

        assertEq(multiStrategyVault.proposedFeeTime(), callTime);
        (
            uint256 deposit,
            uint256 withdrawal,
            uint256 management,
            uint256 performance
        ) = multiStrategyVault.proposedFees();
        assertEq(deposit, 1);
        assertEq(withdrawal, 1);
        assertEq(management, 1);
        assertEq(performance, 1);
    }

    function testFail__proposeFees_nonOwner() public {
        VaultFees memory newVaultFees = VaultFees({
            deposit: 1,
            withdrawal: 1,
            management: 1,
            performance: 1
        });

        vm.prank(alice);
        multiStrategyVault.proposeFees(newVaultFees);
    }

    function testFail__proposeFees_fees_too_high() public {
        VaultFees memory newVaultFees = VaultFees({
            deposit: 1e18,
            withdrawal: 1,
            management: 1,
            performance: 1
        });

        multiStrategyVault.proposeFees(newVaultFees);
    }

    // Change Fees
    function test__changeFees() public {
        VaultFees memory newVaultFees = VaultFees({
            deposit: 1,
            withdrawal: 1,
            management: 1,
            performance: 1
        });
        multiStrategyVault.proposeFees(newVaultFees);

        vm.warp(block.timestamp + 3 days);

        vm.expectEmit(false, false, false, true, address(multiStrategyVault));
        emit ChangedFees(
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            newVaultFees
        );

        multiStrategyVault.changeFees();

        (
            uint256 deposit,
            uint256 withdrawal,
            uint256 management,
            uint256 performance
        ) = multiStrategyVault.fees();
        assertEq(deposit, 1);
        assertEq(withdrawal, 1);
        assertEq(management, 1);
        assertEq(performance, 1);
        (
            uint256 propDeposit,
            uint256 propWithdrawal,
            uint256 propManagement,
            uint256 propPerformance
        ) = multiStrategyVault.proposedFees();
        assertEq(propDeposit, 0);
        assertEq(propWithdrawal, 0);
        assertEq(propManagement, 0);
        assertEq(propPerformance, 0);
        assertEq(multiStrategyVault.proposedFeeTime(), 0);
    }

    function testFail__changeFees_NonOwner() public {
        vm.prank(alice);
        multiStrategyVault.changeFees();
    }

    function testFail__changeFees_respect_rageQuit() public {
        VaultFees memory newVaultFees = VaultFees({
            deposit: 1,
            withdrawal: 1,
            management: 1,
            performance: 1
        });
        multiStrategyVault.proposeFees(newVaultFees);

        // Didnt respect 3 days before propsal and change
        multiStrategyVault.changeFees();
    }

    function testFail__changeFees_after_init() public {
        multiStrategyVault.changeFees();
    }

    /*//////////////////////////////////////////////////////////////
                          SET FEE_RECIPIENT
    //////////////////////////////////////////////////////////////*/

    function test__setFeeRecipient() public {
        vm.expectEmit(false, false, false, true, address(multiStrategyVault));
        emit FeeRecipientUpdated(feeRecipient, alice);

        multiStrategyVault.setFeeRecipient(alice);

        assertEq(multiStrategyVault.feeRecipient(), alice);
    }

    function testFail__setFeeRecipient_NonOwner() public {
        vm.prank(alice);
        multiStrategyVault.setFeeRecipient(alice);
    }

    function testFail__setFeeRecipient_addressZero() public {
        multiStrategyVault.setFeeRecipient(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE ADAPTER
    //////////////////////////////////////////////////////////////*/

    // Propose Adapter
    function test__proposeAdapter() public {
        AdapterConfig[10] memory newAdapters;
        newAdapters[0].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[1].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[2].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[3].adapter = _createAdapter(IERC20(address(asset)));

        newAdapters[0].allocation = 0.1e18;
        newAdapters[1].allocation = 0.2e18;
        newAdapters[2].allocation = 0.3e18;
        newAdapters[3].allocation = 0.4e18;

        uint256 callTime = block.timestamp;

        vm.expectEmit(false, false, false, true, address(multiStrategyVault));
        emit NewAdaptersProposed(newAdapters, 4, callTime);

        multiStrategyVault.proposeAdapters(newAdapters, 4);

        assertEq(multiStrategyVault.proposedAdapterTime(), callTime);

        (IERC4626 gAdapter0, uint256 gAlloc0) = multiStrategyVault
            .proposedAdapters(0);
        (IERC4626 gAdapter1, uint256 gAlloc1) = multiStrategyVault
            .proposedAdapters(1);
        (IERC4626 gAdapter2, uint256 gAlloc2) = multiStrategyVault
            .proposedAdapters(2);
        (IERC4626 gAdapter3, uint256 gAlloc3) = multiStrategyVault
            .proposedAdapters(3);
        assertEq(address(gAdapter0), address(newAdapters[0].adapter));
        assertEq(gAlloc0, newAdapters[0].allocation);
        assertEq(address(gAdapter1), address(newAdapters[1].adapter));
        assertEq(gAlloc1, newAdapters[1].allocation);
        assertEq(address(gAdapter2), address(newAdapters[2].adapter));
        assertEq(gAlloc2, newAdapters[2].allocation);
        assertEq(address(gAdapter3), address(newAdapters[3].adapter));
        assertEq(gAlloc3, newAdapters[3].allocation);
    }

    function testFail__proposeAdapter_nonOwner() public {
        AdapterConfig[10] memory newAdapters;
        newAdapters[0].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[0].allocation = 0.1e18;

        vm.prank(alice);
        multiStrategyVault.proposeAdapters(newAdapters, 1);
    }

    function testFail__proposeAdapter_asset_missmatch() public {
        MockERC20 newAsset = new MockERC20("New Mock Token", "NTKN", 18);
        AdapterConfig[10] memory newAdapters;
        newAdapters[0].adapter = _createAdapter(IERC20(address(newAsset)));
        newAdapters[0].allocation = 0.1e18;

        vm.prank(alice);
        multiStrategyVault.proposeAdapters(newAdapters, 1);
    }

    // Change Adapter
    function test__changeAdapter() public {
        AdapterConfig[10] memory newAdapters;
        newAdapters[0].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[1].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[2].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[3].adapter = _createAdapter(IERC20(address(asset)));

        newAdapters[0].allocation = 0.1e18;
        newAdapters[1].allocation = 0.2e18;
        newAdapters[2].allocation = 0.3e18;
        newAdapters[3].allocation = 0.4e18;
        uint256 depositAmount = 1 ether;

        // Deposit funds for testing
        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(multiStrategyVault), depositAmount);
        multiStrategyVault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Increase assets in asset Adapter to check hwm and assetCheckpoint later
        asset.mint(
            address(adapters[0].adapter),
            depositAmount.mulDivDown(adapters[0].allocation, 1e18)
        );
        asset.mint(
            address(adapters[1].adapter),
            depositAmount.mulDivDown(adapters[1].allocation, 1e18)
        );
        asset.mint(
            address(adapters[2].adapter),
            depositAmount.mulDivDown(adapters[2].allocation, 1e18)
        );
        multiStrategyVault.takeManagementAndPerformanceFees();
        uint256 oldHWM = multiStrategyVault.highWaterMark();

        // Preparation to change the adapter
        multiStrategyVault.proposeAdapters(newAdapters, 4);

        vm.warp(block.timestamp + 3 days);

        vm.expectEmit(false, false, false, true, address(multiStrategyVault));
        emit ChangedAdapters(adapters, 3, newAdapters, 4);

        multiStrategyVault.changeAdapters();

        // Annoyingly Math fails us here and leaves 1 asset in the adapter
        assertEq(
            asset.allowance(
                address(multiStrategyVault),
                address(adapters[0].adapter)
            ),
            0
        );
        assertEq(
            asset.allowance(
                address(multiStrategyVault),
                address(adapters[1].adapter)
            ),
            0
        );
        assertEq(
            asset.allowance(
                address(multiStrategyVault),
                address(adapters[2].adapter)
            ),
            0
        );

        assertEq(
            asset.allowance(
                address(multiStrategyVault),
                address(newAdapters[0].adapter)
            ),
            type(uint256).max
        );
        assertEq(
            asset.allowance(
                address(multiStrategyVault),
                address(newAdapters[1].adapter)
            ),
            type(uint256).max
        );
        assertEq(
            asset.allowance(
                address(multiStrategyVault),
                address(newAdapters[2].adapter)
            ),
            type(uint256).max
        );
        assertEq(
            asset.allowance(
                address(multiStrategyVault),
                address(newAdapters[3].adapter)
            ),
            type(uint256).max
        );

        assertEq(asset.balanceOf(address(adapters[0].adapter)), 1);
        assertEq(asset.balanceOf(address(adapters[1].adapter)), 1);
        assertEq(asset.balanceOf(address(adapters[2].adapter)), 1);

        assertEq(adapters[0].adapter.balanceOf(address(multiStrategyVault)), 0);
        assertEq(adapters[1].adapter.balanceOf(address(multiStrategyVault)), 0);
        assertEq(adapters[2].adapter.balanceOf(address(multiStrategyVault)), 0);

        assertEq(
            asset.balanceOf(address(newAdapters[0].adapter)),
            (depositAmount * 2 - 3).mulDivDown(newAdapters[0].allocation, 1e18)
        );
        assertEq(
            asset.balanceOf(address(newAdapters[1].adapter)),
            (depositAmount * 2 - 3).mulDivDown(newAdapters[1].allocation, 1e18)
        );
        assertEq(
            asset.balanceOf(address(newAdapters[2].adapter)),
            (depositAmount * 2 - 3).mulDivDown(newAdapters[2].allocation, 1e18)
        );
        assertEq(
            asset.balanceOf(address(newAdapters[3].adapter)),
            (depositAmount * 2 - 3).mulDivDown(newAdapters[3].allocation, 1e18)
        );

        assertEq(
            newAdapters[0].adapter.balanceOf(address(multiStrategyVault)),
            (depositAmount * 2 - 3).mulDivDown(
                newAdapters[0].allocation,
                1e18
            ) * 1e9
        );
        assertEq(
            newAdapters[1].adapter.balanceOf(address(multiStrategyVault)),
            (depositAmount * 2 - 3).mulDivDown(
                newAdapters[1].allocation,
                1e18
            ) * 1e9
        );
        assertEq(
            newAdapters[2].adapter.balanceOf(address(multiStrategyVault)),
            (depositAmount * 2 - 3).mulDivDown(
                newAdapters[2].allocation,
                1e18
            ) * 1e9
        );
        assertEq(
            newAdapters[3].adapter.balanceOf(address(multiStrategyVault)),
            (depositAmount * 2 - 3).mulDivDown(
                newAdapters[3].allocation,
                1e18
            ) * 1e9
        );

        assertEq(multiStrategyVault.highWaterMark(), oldHWM);

        assertEq(multiStrategyVault.proposedAdapterTime(), 0);
        (IERC4626 gAdapter0, ) = multiStrategyVault.proposedAdapters(0);
        (IERC4626 gAdapter1, ) = multiStrategyVault.proposedAdapters(1);
        (IERC4626 gAdapter2, ) = multiStrategyVault.proposedAdapters(2);
        (IERC4626 gAdapter3, ) = multiStrategyVault.proposedAdapters(3);
        assertEq(address(gAdapter0), address(0));
        assertEq(address(gAdapter1), address(0));
        assertEq(address(gAdapter2), address(0));
        assertEq(address(gAdapter3), address(0));
    }

    function testFail__changeAdapter_NonOwner() public {
        vm.prank(alice);
        multiStrategyVault.changeAdapters();
    }

    function testFail__changeAdapter_respect_rageQuit() public {
        AdapterConfig[10] memory newAdapters;
        newAdapters[0].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[1].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[2].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[3].adapter = _createAdapter(IERC20(address(asset)));

        newAdapters[0].allocation = 0.1e18;
        newAdapters[1].allocation = 0.2e18;
        newAdapters[2].allocation = 0.3e18;
        newAdapters[3].allocation = 0.4e18;

        multiStrategyVault.proposeAdapters(newAdapters, 4);

        // Didnt respect 3 days before propsal and change
        multiStrategyVault.changeAdapters();
    }

    function testFail__changeAdapter_after_init() public {
        multiStrategyVault.changeAdapters();
    }

    function testFail__changeAdapter_instantly_again() public {
        AdapterConfig[10] memory newAdapters;
        newAdapters[0].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[1].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[2].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[3].adapter = _createAdapter(IERC20(address(asset)));

        newAdapters[0].allocation = 0.1e18;
        newAdapters[1].allocation = 0.2e18;
        newAdapters[2].allocation = 0.3e18;
        newAdapters[3].allocation = 0.4e18;
        uint256 depositAmount = 1 ether;

        // Deposit funds for testing
        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(multiStrategyVault), depositAmount);
        multiStrategyVault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Increase assets in asset Adapter to check hwm and assetCheckpoint later
        asset.mint(
            address(adapters[0].adapter),
            depositAmount.mulDivDown(adapters[0].allocation, 1e18)
        );
        asset.mint(
            address(adapters[1].adapter),
            depositAmount.mulDivDown(adapters[1].allocation, 1e18)
        );
        asset.mint(
            address(adapters[2].adapter),
            depositAmount.mulDivDown(adapters[2].allocation, 1e18)
        );
        multiStrategyVault.takeManagementAndPerformanceFees();

        // Preparation to change the adapter
        multiStrategyVault.proposeAdapters(newAdapters, 4);

        vm.warp(block.timestamp + 3 days);

        vm.expectEmit(false, false, false, true, address(multiStrategyVault));
        emit ChangedAdapters(adapters, 3, newAdapters, 4);

        multiStrategyVault.changeAdapters();
        multiStrategyVault.changeAdapters();
    }

    /*//////////////////////////////////////////////////////////////
                          SET RAGE QUIT
    //////////////////////////////////////////////////////////////*/

    function test__setQuitPeriod() public {
        // Pass the inital quit period
        vm.warp(block.timestamp + 3 days);

        uint256 newQuitPeriod = 1 days;
        vm.expectEmit(false, false, false, true, address(multiStrategyVault));
        emit QuitPeriodSet(newQuitPeriod);

        multiStrategyVault.setQuitPeriod(newQuitPeriod);

        assertEq(multiStrategyVault.quitPeriod(), newQuitPeriod);
    }

    function testFail__setQuitPeriod_NonOwner() public {
        vm.prank(alice);
        multiStrategyVault.setQuitPeriod(1 days);
    }

    function testFail__setQuitPeriod_too_low() public {
        multiStrategyVault.setQuitPeriod(23 hours);
    }

    function testFail__setQuitPeriod_too_high() public {
        multiStrategyVault.setQuitPeriod(8 days);
    }

    function testFail__setQuitPeriod_during_initial_quitPeriod() public {
        multiStrategyVault.setQuitPeriod(1 days);
    }

    function testFail__setQuitPeriod_during_adapter_quitPeriod() public {
        AdapterConfig[10] memory newAdapters;
        newAdapters[0].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[1].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[2].adapter = _createAdapter(IERC20(address(asset)));
        newAdapters[3].adapter = _createAdapter(IERC20(address(asset)));

        newAdapters[0].allocation = 0.1e18;
        newAdapters[1].allocation = 0.2e18;
        newAdapters[2].allocation = 0.3e18;
        newAdapters[3].allocation = 0.4e18;

        // Pass the inital quit period
        vm.warp(block.timestamp + 3 days);

        multiStrategyVault.proposeAdapters(newAdapters, 4);

        multiStrategyVault.setQuitPeriod(1 days);
    }

    function testFail__setQuitPeriod_during_fee_quitPeriod() public {
        // Pass the inital quit period
        vm.warp(block.timestamp + 3 days);

        multiStrategyVault.proposeFees(
            VaultFees({
                deposit: 1,
                withdrawal: 1,
                management: 1,
                performance: 1
            })
        );

        multiStrategyVault.setQuitPeriod(1 days);
    }

    /*//////////////////////////////////////////////////////////////
                          SET DEPOSIT LIMIT
    //////////////////////////////////////////////////////////////*/

    function test__setDepositLimit() public {
        uint256 newDepositLimit = 100;
        vm.expectEmit(false, false, false, true, address(multiStrategyVault));
        emit DepositLimitSet(newDepositLimit);

        multiStrategyVault.setDepositLimit(newDepositLimit);

        assertEq(multiStrategyVault.depositLimit(), newDepositLimit);

        asset.mint(address(this), 101);
        asset.approve(address(multiStrategyVault), 101);

        vm.expectRevert(
            abi.encodeWithSelector(MultiStrategyVault.MaxError.selector, 101)
        );
        multiStrategyVault.deposit(101, address(this));

        vm.expectRevert(
            abi.encodeWithSelector(
                MultiStrategyVault.MaxError.selector,
                101 * 1e9
            )
        );
        multiStrategyVault.mint(101 * 1e9, address(this));
    }

    function testFail__setDepositLimit_NonOwner() public {
        vm.prank(alice);
        multiStrategyVault.setDepositLimit(uint256(100));
    }

    /*//////////////////////////////////////////////////////////////
                                PAUSE
    //////////////////////////////////////////////////////////////*/

    // Pause
    function test__pause() public {
        uint256 depositAmount = 1 ether;

        // Deposit funds for testing
        asset.mint(alice, depositAmount * 3);
        vm.startPrank(alice);
        asset.approve(address(multiStrategyVault), depositAmount * 3);
        multiStrategyVault.deposit(depositAmount * 2, alice);
        vm.stopPrank();

        vm.expectEmit(false, false, false, true, address(multiStrategyVault));
        emit Paused(address(this));

        multiStrategyVault.pause();

        assertTrue(multiStrategyVault.paused());

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        multiStrategyVault.deposit(depositAmount, alice);

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        multiStrategyVault.mint(depositAmount, alice);

        vm.prank(alice);
        multiStrategyVault.withdraw(depositAmount, alice, alice);

        vm.prank(alice);
        multiStrategyVault.redeem(depositAmount, alice, alice);
    }

    function testFail__pause_nonOwner() public {
        vm.prank(alice);
        multiStrategyVault.pause();
    }

    // Unpause
    // function test__unpause() public {
    //   uint256 depositAmount = 1 ether;

    //   // Deposit funds for testing
    //   asset.mint(alice, depositAmount * 2);
    //   vm.prank(alice);
    //   asset.approve(address(multiStrategyVault), depositAmount * 2);

    //   multiStrategyVault.pause();

    //   vm.expectEmit(false, false, false, true, address(multiStrategyVault));
    //   emit Unpaused(address(this));

    //   multiStrategyVault.unpause();

    //   assertFalse(multiStrategyVault.paused());

    //   vm.prank(alice);
    //   multiStrategyVault.deposit(depositAmount, alice);
    //   emit log_named_uint("max withdraw", multiStrategyVault.maxWithdraw(alice));

    //   vm.prank(alice);
    //   multiStrategyVault.mint(depositAmount, alice);
    //   emit log_named_uint("max redeem", multiStrategyVault.maxRedeem(alice));

    //   vm.prank(alice);
    //   multiStrategyVault.withdraw(depositAmount, alice, alice);
    //   emit log_named_uint("max withdraw", multiStrategyVault.maxWithdraw(alice));

    //   emit log_named_uint("max redeem", multiStrategyVault.maxRedeem(alice));

    //   vm.prank(alice);
    //   multiStrategyVault.redeem(depositAmount, alice, alice);
    // }

    function testFail__unpause_nonOwner() public {
        multiStrategyVault.pause();

        vm.prank(alice);
        multiStrategyVault.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                              PERMIT
    //////////////////////////////////////////////////////////////*/

    function test_permit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    multiStrategyVault.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        multiStrategyVault.permit(
            owner,
            address(0xCAFE),
            1e18,
            block.timestamp,
            v,
            r,
            s
        );

        assertEq(multiStrategyVault.allowance(owner, address(0xCAFE)), 1e18);
        assertEq(multiStrategyVault.nonces(owner), 1);
    }
}