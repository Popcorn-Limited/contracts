// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {MaticXLooper, BaseAaveLeverageStrategy, LooperValues, LooperBaseValues, IERC20, IMaticXPool} from "src/strategies/stader/MaticXLooper.sol";
import {IERC20Metadata, ILendingPool, Math} from "src/strategies/BaseAaveLeverageStrategy.sol";

import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, Math} from "../BaseStrategyTest.sol";
import "forge-std/console.sol";

contract MaticXLooperTest is BaseStrategyTest {
    using stdJson for string;
    using Math for uint256;

    IERC20 maticX;
    IERC20 aMaticX;
    IERC20 vdWMatic;
    ILendingPool lendingPool;
    MaticXLooper strategyContract;
    IMaticXPool maticXPool =
        IMaticXPool(0xfd225C9e6601C9d38d8F98d8731BF59eFcF8C0E3);

    uint256 defaultAmount;
    uint256 slippage;

    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/stader/MaticXLooperTestConfig.json"
        );
    }

    function _setUpStrategy(
        string memory json_,
        string memory index_,
        TestConfig memory testConfig_
    ) internal override returns (IBaseStrategy) {
        // Read strategy init values
        LooperBaseValues memory baseValues = abi.decode(
            json_.parseRaw(
                string.concat(".configs[", index_, "].specific.base")
            ),
            (LooperBaseValues)
        );

        LooperValues memory looperInitValues = abi.decode(
            json_.parseRaw(
                string.concat(".configs[", index_, "].specific.init")
            ),
            (LooperValues)
        );

        // Deploy Strategy
        MaticXLooper strategy = new MaticXLooper();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(baseValues, looperInitValues)
        );

        strategyContract = MaticXLooper(payable(strategy));
        vm.startPrank(address(strategyContract));
        payable(bob).call{value: address(strategyContract).balance}("");
        vm.stopPrank();

        maticX = IERC20(testConfig_.asset);
        aMaticX = strategyContract.interestToken();
        vdWMatic = strategyContract.debtToken();
        lendingPool = strategyContract.lendingPool();
        defaultAmount = testConfig_.defaultAmount;
        slippage = strategyContract.slippage();

        deal(testConfig_.asset, address(this), 1);
        IERC20(testConfig_.asset).approve(address(strategy), 1);
        strategyContract.setUserUseReserveAsCollateral(1);

        return IBaseStrategy(address(strategy));
    }

    // Verify that totalAssets returns the expected amount
    function test__verify_totalAssets() public {
        // Make sure totalAssets isnt 0
        deal(address(maticX), bob, defaultAmount);
        vm.startPrank(bob);
        maticX.approve(address(strategy), defaultAmount);
        strategy.deposit(defaultAmount, bob);
        vm.stopPrank();

        assertApproxEqAbs(
            strategy.totalAssets(),
            strategy.convertToAssets(strategy.totalSupply()),
            _delta_,
            string.concat("totalSupply converted != totalAssets")
        );
    }

    function increasePricePerShare(uint256 amount) public {
        deal(address(maticX), address(strategy), amount);
        vm.startPrank(address(strategy));
        lendingPool.supply(address(maticX), amount, address(strategy), 0);
        vm.stopPrank();
    }

    function test__initialization() public override {
        LooperBaseValues memory baseValues = abi.decode(
            json.parseRaw(
                string.concat(".configs[0].specific.base")
            ),
            (LooperBaseValues)
        );

        LooperValues memory looperInitValues = abi.decode(
            json.parseRaw(string.concat(".configs[0].specific.init")),
            (LooperValues)
        );

        // Deploy Strategy
        MaticXLooper strategy = new MaticXLooper();

        strategy.initialize(
            testConfig.asset,
            address(this),
            true,
            abi.encode(baseValues, looperInitValues)
        );

        verify_adapterInit();
    }

    function test__deposit(uint8 fuzzAmount) public override {
        uint256 len = json.readUint(".length");
        for (uint256 i; i < len; i++) {
            if (i > 0) _setUpBaseTest(i, path);

            uint256 amount = bound(
                fuzzAmount,
                testConfig.minDeposit,
                testConfig.maxDeposit
            );

            _mintAssetAndApproveForStrategy(amount, bob);

            prop_deposit(bob, bob, amount, testConfig.testId);

            _increasePricePerShare(testConfig.defaultAmount * 1_000);

            _mintAssetAndApproveForStrategy(amount, bob);
            prop_deposit(bob, alice, amount, testConfig.testId);
        }
    }

    function test__withdraw(uint8 fuzzAmount) public override {
        uint256 len = json.readUint(".length");
        for (uint256 i; i < len; i++) {
            if (i > 0) _setUpBaseTest(i, path);

            uint256 amount = bound(
                fuzzAmount,
                testConfig.minDeposit,
                testConfig.maxDeposit
            );

            uint256 reqAssets = strategy.previewMint(
                strategy.previewWithdraw(amount)
            );
            _mintAssetAndApproveForStrategy(reqAssets, bob);
            vm.prank(bob);
            strategy.deposit(reqAssets, bob);

            prop_withdraw(
                bob,
                bob,
                strategy.maxWithdraw(bob),
                testConfig.testId
            );

            _mintAssetAndApproveForStrategy(reqAssets, bob);
            vm.prank(bob);
            strategy.deposit(reqAssets, bob);

            _increasePricePerShare(testConfig.defaultAmount * 1_000);

            vm.prank(bob);
            strategy.approve(alice, type(uint256).max);

            prop_withdraw(
                alice,
                bob,
                strategy.maxWithdraw(bob),
                testConfig.testId
            );
        }
    }

    function test__setHarvestValues() public {
        bytes32 poolId = hex"cd78a30c597e367a4e478a2411ceb790604d7c8f000000000000000000000c22";
        address oldPool = address(strategyContract.balancerVault());
        address newPool = address(0x85dE3ADd465a219EE25E04d22c39aB027cF5C12E);
        address asset = strategy.asset();

        strategyContract.setHarvestValues(abi.encode(newPool, poolId));
        uint256 oldAllowance = IERC20(asset).allowance(
            address(strategy),
            oldPool
        );
        uint256 newAllowance = IERC20(asset).allowance(
            address(strategy),
            newPool
        );

        assertEq(address(strategyContract.balancerVault()), newPool);
        assertEq(oldAllowance, 0);
        assertEq(newAllowance, type(uint256).max);
        assertEq(strategyContract.balancerPoolId(), poolId);
    }

    function test__deposit_manual() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(maticX), bob, amountMint);

        vm.startPrank(bob);
        maticX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // check total assets
        assertEq(strategy.totalAssets(), amountDeposit);

        // maticX should be in lending market
        assertEq(maticX.balanceOf(address(strategy)), 0);

        // adapter should hold maticX aToken in equal amount
        assertEq(aMaticX.balanceOf(address(strategy)), amountDeposit + 1);

        // adapter should not hold debt at this poin
        assertEq(vdWMatic.balanceOf(address(strategy)), 0);

        // LTV should still be 0
        assertEq(strategyContract.getLTV(), 0);
    }

    function test__adjustLeverage_only_flashLoan_maticX_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(maticX), bob, amountMint);

        // send the adapter some maticX dust
        deal(address(strategy), 0.01e18);

        vm.startPrank(bob);
        maticX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        // check total assets - should be lt than totalDeposits
        assertLt(strategy.totalAssets(), amountDeposit * 2);

        // all maticX should be in lending market
        assertEq(maticX.balanceOf(address(strategy)), 0);

        // adapter should now have more maticX aToken than before
        assertGt(aMaticX.balanceOf(address(strategy)), amountDeposit);

        // adapter should hold debt tokens
        assertGt(vdWMatic.balanceOf(address(strategy)), 0);

        // LTV is non zero now
        assertGt(strategyContract.getLTV(), 0);

        // LTV is slightly lower target, since some maticX means extra collateral
        assertGt(strategyContract.targetLTV(), strategyContract.getLTV());
    }

    function test__adjustLeverage_only_flashLoan() public {
        uint256 amountMint = 1e18;
        uint256 amountDeposit = 1e18;

        deal(address(maticX), bob, amountMint);

        vm.startPrank(bob);
        maticX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        // check total assets - should be lt than totalDeposits
        assertLt(strategy.totalAssets(), amountDeposit);

        (uint256 slippageDebt, , ) = maticXPool.convertMaticToMaticX(
            vdWMatic.balanceOf(address(strategy))
        );

        slippageDebt = slippageDebt.mulDiv(slippage, 1e18, Math.Rounding.Ceil);

        assertApproxEqAbs(
            strategy.totalAssets(),
            amountDeposit - slippageDebt,
            _delta_,
            string.concat("totalAssets != expected")
        );

        // // maticX should be in lending market
        assertEq(maticX.balanceOf(address(strategy)), 0);

        // // adapter should now have more maticX aToken than before
        assertGt(aMaticX.balanceOf(address(strategy)), amountDeposit);

        // adapter should hold debt tokens
        assertGt(vdWMatic.balanceOf(address(strategy)), 0);

        // LTV is non zero now
        assertGt(strategyContract.getLTV(), 0);

        // LTV is at target - or 1 wei delta for approximation up of ltv
        assertApproxEqAbs(
            strategyContract.targetLTV(),
            strategyContract.getLTV(),
            _delta_,
            string.concat("ltv != expected")
        );
    }

    function test__adjustLeverage_flashLoan_and_eth_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(maticX), bob, amountMint);

        vm.startPrank(bob);
        maticX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        uint256 totAssetsBefore = strategy.totalAssets();

        vm.deal(address(strategy), 1e18);

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        // tot assets increased in this case
        // but if the amount of dust is lower than the slippage % of debt
        // totalAssets would be lower, as leverage incurred in debt
        assertGt(strategy.totalAssets(), totAssetsBefore);

        // maticX should be in lending market
        assertEq(maticX.balanceOf(address(strategy)), 0);

        // adapter should now have more maticX aToken than before
        assertGt(aMaticX.balanceOf(address(strategy)), amountDeposit);

        // adapter should hold debt tokens
        assertGt(vdWMatic.balanceOf(address(strategy)), 0);

        // LTV is non zero now
        assertGt(strategyContract.getLTV(), 0);

        // LTV is slightly below target, since some eth dust has been deposited as collateral
        assertGt(strategyContract.targetLTV(), strategyContract.getLTV());
    }

    function test__adjustLeverage_only_matic_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountDust = 10e18;

        deal(address(maticX), bob, amountMint);

        vm.startPrank(bob);
        maticX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // SEND Matic TO CONTRACT
        vm.deal(address(strategy), amountDust);

        // adjust leverage - should only trigger a dust amount deposit - no flashloans
        strategyContract.adjustLeverage();

        // check total assets - should be gt than totalDeposits
        assertGt(strategy.totalAssets(), amountDeposit);

        // maticX should be in lending market
        assertEq(maticX.balanceOf(address(strategy)), 0);

        // adapter should now have more maticX aToken than before
        assertGt(aMaticX.balanceOf(address(strategy)), amountDeposit);

        // adapter should not hold debt tokens
        assertEq(vdWMatic.balanceOf(address(strategy)), 0);

        // adapter should now have 0 eth dust
        assertEq(address(strategy).balance, 0);

        // LTV is still zero
        assertEq(strategyContract.getLTV(), 0);
    }

    function test__leverageDown() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;

        deal(address(maticX), bob, amountMint);

        vm.startPrank(bob);
        maticX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        vm.prank(bob);
        strategy.withdraw(amountWithdraw, bob, bob);

        // after withdraw, vault ltv is a bit higher than target, considering the anti slipage amount witdrawn
        uint256 currentLTV = strategyContract.getLTV();
        assertGt(currentLTV, strategyContract.targetLTV());

        // HARVEST - should reduce leverage closer to target since we are above target LTV
        strategyContract.adjustLeverage();

        // ltv before should be higher than now
        assertGt(currentLTV, strategyContract.getLTV());
    }

    function test__withdraw_manual() public {
        uint256 amountMint = 1e18;
        uint256 amountDeposit = 1e18;

        deal(address(maticX), bob, amountMint);

        vm.startPrank(bob);
        maticX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop - get debt
        strategyContract.adjustLeverage();

        // withdraw full amount - repay full debt
        vm.startPrank(bob);
        strategy.redeem(IERC20(address(strategy)).balanceOf(bob), bob, bob);
        vm.stopPrank();

        // check total assets
        uint256 expDust = amountDeposit.mulDiv(
            slippage,
            1e18,
            Math.Rounding.Floor
        );
        assertApproxEqAbs(strategy.totalAssets(), expDust, _delta_, "TA");

        assertEq(IERC20(address(strategy)).totalSupply(), 0);

        // should not hold any maticX aToken
        assertEq(aMaticX.balanceOf(address(strategy)), 0);

        // adapter should not hold debt any debt
        assertEq(vdWMatic.balanceOf(address(strategy)), 0);
    }

    function test_withdraw_dust() public {
        // manager can withdraw maticX balance when vault total supply is 0
        deal(address(maticX), address(strategy), 10e18);

        vm.prank(address(this));
        strategyContract.withdrawDust(address(this));

        assertEq(strategy.totalAssets(), 0, "TA");
    }

    function test_withdraw_dust_invalid() public {
        // manager can not withdraw maticX balance when vault total supply is > 0
        deal(address(maticX), address(bob), 10e18);

        vm.startPrank(bob);
        maticX.approve(address(strategy), 10e18);
        strategy.deposit(10e18, bob);
        vm.stopPrank();

        uint256 totAssetsBefore = strategy.totalAssets();
        uint256 maticXOwnerBefore = IERC20(address(maticX)).balanceOf(
            address(this)
        );

        vm.prank(address(this));
        strategyContract.withdrawDust(address(this));

        assertEq(strategy.totalAssets(), totAssetsBefore, "TA DUST");
        assertEq(
            IERC20(address(maticX)).balanceOf(address(this)),
            maticXOwnerBefore,
            "OWNER DUST"
        );
    }

    function test__setLeverageValues_lever_up() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(maticX), bob, amountMint);

        vm.startPrank(bob);
        maticX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        uint256 oldABalance = aMaticX.balanceOf(address(strategy));
        uint256 oldLTV = strategyContract.getLTV();

        strategyContract.setLeverageValues(8.5e17, 8.8e17);

        assertGt(aMaticX.balanceOf(address(strategy)), oldABalance);
        assertGt(strategyContract.getLTV(), oldLTV);
    }

    function test__setLeverageValues_lever_down() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(maticX), bob, amountMint);

        vm.startPrank(bob);
        maticX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        uint256 oldABalance = aMaticX.balanceOf(address(strategy));
        uint256 oldLTV = strategyContract.getLTV();

        strategyContract.setLeverageValues(3e17, 4e17);

        assertLt(aMaticX.balanceOf(address(strategy)), oldABalance);
        assertLt(strategyContract.getLTV(), oldLTV);
    }

    function test__setLeverageValues_invalidInputs() public {
        // protocolLTV < targetLTV < maxLTV
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseAaveLeverageStrategy.InvalidLTV.selector,
                3e18,
                4e18,
                strategyContract.protocolMaxLTV()
            )
        );
        strategyContract.setLeverageValues(3e18, 4e18);

        // maxLTV < targetLTV < protocolLTV
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseAaveLeverageStrategy.InvalidLTV.selector,
                4e17,
                3e17,
                strategyContract.protocolMaxLTV()
            )
        );
        strategyContract.setLeverageValues(4e17, 3e17);
    }

    function test__setSlippage() public {
        uint256 oldSlippage = strategyContract.slippage();
        uint256 newSlippage = oldSlippage + 1;
        strategyContract.setSlippage(newSlippage);

        assertNotEq(oldSlippage, strategyContract.slippage());
        assertEq(strategyContract.slippage(), newSlippage);
    }

    function test__setSlippage_invalidValue() public {
        uint256 newSlippage = 1e18; // 100%

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseAaveLeverageStrategy.InvalidSlippage.selector,
                newSlippage,
                2e17
            )
        );
        strategyContract.setSlippage(newSlippage);
    }

    function test__invalid_flashLoan() public {
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory premiums = new uint256[](1);

        // reverts with invalid msg.sender and valid initiator
        vm.expectRevert(BaseAaveLeverageStrategy.NotFlashLoan.selector);
        vm.prank(bob);
        strategyContract.executeOperation(
            assets,
            amounts,
            premiums,
            address(strategy),
            ""
        );

        // reverts with invalid initiator and valid msg.sender
        vm.expectRevert(BaseAaveLeverageStrategy.NotFlashLoan.selector);
        vm.prank(address(lendingPool));
        strategyContract.executeOperation(
            assets,
            amounts,
            premiums,
            address(bob),
            ""
        );
    }

    // function test__harvest() public override {
    //     _mintAssetAndApproveForStrategy(100e18, bob);

    //     vm.prank(bob);
    //     strategy.deposit(100e18, bob);

    //     // LTV should be 0
    //     assertEq(strategyContract.getLTV(), 0);

    //     strategy.harvest(hex"");

    //     // LTV should be at target now
    //     assertApproxEqAbs(
    //         strategyContract.targetLTV(),
    //         strategyContract.getLTV(),
    //         _delta_,
    //         string.concat("ltv != expected")
    //     );
    // }

    function test__leverUp() public {
        uint256 amountDeposit = 1e18;
        deal(address(maticX), bob, amountDeposit);

        vm.startPrank(bob);
        maticX.approve(address(strategy), amountDeposit);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        uint256 initialABalance = aMaticX.balanceOf(address(strategy));
        uint256 initialLTV = strategyContract.getLTV();
        uint256 depositAmount = 0.5e18; // Example deposit amount

        // Call leverUp with a specific deposit amount
        strategyContract.leverUp(depositAmount);

        uint256 finalABalance = aMaticX.balanceOf(address(strategy));
        uint256 finalLTV = strategyContract.getLTV();

        // Check that the aToken balance has increased
        assertGt(
            finalABalance,
            initialABalance,
            "aToken balance should increase after leverUp"
        );

        // Check that the LTV has increased
        assertGt(finalLTV, initialLTV, "LTV should increase after leverUp");

        // Check that the final LTV is not above the max LTV
        assertLe(
            finalLTV,
            strategyContract.maxLTV(),
            "Final LTV should not exceed max LTV"
        );
    }

    function test__leverDown() public {
        uint256 amountDeposit = 1e18;
        deal(address(maticX), bob, amountDeposit);

        vm.startPrank(bob);
        maticX.approve(address(strategy), amountDeposit);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // First, lever up to create some debt
        strategyContract.leverUp(0.5e18);

        uint256 initialABalance = aMaticX.balanceOf(address(strategy));
        uint256 initialLTV = strategyContract.getLTV();
        uint256 borrowAmount = 0.2e18; // Example borrow amount to reduce
        uint256 slippage = 1e16; // 1% slippage

        // Now call leverDown
        strategyContract.leverDown(borrowAmount, slippage);

        uint256 finalABalance = aMaticX.balanceOf(address(strategy));
        uint256 finalLTV = strategyContract.getLTV();

        // Check that the aToken balance has decreased
        assertLt(
            finalABalance,
            initialABalance,
            "aToken balance should decrease after leverDown"
        );

        // Check that the LTV has decreased
        assertLt(finalLTV, initialLTV, "LTV should decrease after leverDown");

        // Check that the final LTV is not above the max LTV
        assertLe(
            finalLTV,
            strategyContract.maxLTV(),
            "Final LTV should not exceed max LTV"
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public {
        assertEq(strategy.asset(), address(maticX), "asset");
        assertEq(
            IERC20Metadata(address(strategy)).name(),
            string.concat(
                "VaultCraft Leveraged ",
                IERC20Metadata(address(maticX)).name(),
                " Strategy"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(strategy)).symbol(),
            string.concat("vc-", IERC20Metadata(address(maticX)).symbol()),
            "symbol"
        );

        assertApproxEqAbs(
            maticX.allowance(address(strategy), address(lendingPool)),
            type(uint256).max,
            1,
            "allowance"
        );
    }
}
