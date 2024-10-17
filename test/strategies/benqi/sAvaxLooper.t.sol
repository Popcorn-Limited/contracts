// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {sAVAXLooper, BaseCompoundV2LeverageStrategy, LooperValues, LooperBaseValues, IERC20, IAvaxStaking} from "src/strategies/benqi/sAVAXLooper.sol";
import {IERC20Metadata, ILendingPool, Math, ICToken} from "src/strategies/BaseCompV2LeverageStrategy.sol";

import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, Math} from "../BaseStrategyTest.sol";
import "forge-std/console.sol";

contract sAVAXLooperTest is BaseStrategyTest {
    using stdJson for string;
    using Math for uint256;

    IERC20 wAVAX; // borrow token
    ICToken csAVAX; // cToken for sAvax
    ICToken cwAVAX; // cToken for wAvax
    IERC20 sAvax; // asset
    ILendingPool aaveLendingPool;
    sAVAXLooper strategyContract;
    IAvaxStaking sAvaxStaking =
        IAvaxStaking(0x2b2C81e08f1Af8835a78Bb2A90AE924ACE0eA4bE);

    uint256 defaultAmount;
    uint256 slippage;


    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/benqi/sAvaxLooperTestConfig.json"
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
        sAVAXLooper strategy = new sAVAXLooper();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(baseValues, looperInitValues)
        );

        strategyContract = sAVAXLooper(payable(strategy));
        vm.startPrank(address(strategyContract));
        payable(bob).call{value: address(strategyContract).balance}("");
        vm.stopPrank();

        sAvax = IERC20(testConfig_.asset);
        csAVAX = strategyContract.collateralToken();
        cwAVAX = strategyContract.borrowCToken();
        wAVAX = IERC20(strategyContract.borrowAsset());

        aaveLendingPool = strategyContract.aaveLendingPool();
        defaultAmount = testConfig_.defaultAmount;
        slippage = strategyContract.slippage();

        // deal(testConfig_.asset, address(this), 1);
        // IERC20(testConfig_.asset).approve(address(strategy), 1);
        // strategyContract.setUserUseReserveAsCollateral(1);

        return IBaseStrategy(address(strategy));
    }

    // Verify that totalAssets returns the expected amount
    function test__verify_totalAssets() public {
        // Make sure totalAssets isnt 0
        deal(address(sAvax), bob, defaultAmount);
        vm.startPrank(bob);
        sAvax.approve(address(strategy), defaultAmount);
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
        deal(address(sAvax), address(strategy), amount);
        vm.startPrank(address(strategy));
        aaveLendingPool.supply(address(sAvax), amount, address(strategy), 0);
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
        sAVAXLooper strategy = new sAVAXLooper();

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

        deal(address(sAvax), bob, amountMint);
        vm.startPrank(bob);
        sAvax.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        uint256 balance = IERC20(address(csAVAX)).balanceOf(address(strategy));
        uint256 rate = strategyContract.exchangeRate(address(csAVAX));
        uint256 expectedUnderlying = balance.mulDiv(rate, 1e18, Math.Rounding.Floor);

        // check total assets
        assertApproxEqAbs(
            strategy.totalAssets(),
            expectedUnderlying,
            1,
            string.concat("totalAssets != expected")
        );

        // sAvax should be in lending market
        assertEq(sAvax.balanceOf(address(strategy)), 0);

        // adapter should hold sAvax aToken in equal amount
        assertEq(csAVAX.balanceOf(address(strategy)), expectedUnderlying.mulDiv(1e18, rate, Math.Rounding.Ceil));

        // adapter should not hold debt at this poin
        assertEq(cwAVAX.balanceOf(address(strategy)), 0);

        // LTV should still be 0
        assertEq(strategyContract.getLTV(), 0);
    }

    function test__adjustLeverage_only_flashLoan_sAvax_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(sAvax), bob, amountMint);

        // send the adapter some sAvax dust
        deal(address(strategy), 0.01e18);

        vm.startPrank(bob);
        sAvax.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        // check total assets - should be lt than totalDeposits
        assertLt(strategy.totalAssets(), amountDeposit * 2);

        // all sAvax should be in lending market
        assertEq(sAvax.balanceOf(address(strategy)), 0);

        // adapter should now have more sAvax aToken than before
        assertGt(csAVAX.balanceOf(address(strategy)) * 1e8, amountDeposit);

        // LTV is non zero now
        assertGt(strategyContract.getLTV(), 0);

        // LTV is slightly lower target, since some sAvax means extra collateral
        assertApproxEqAbs(
            strategyContract.targetLTV(),
            strategyContract.getLTV(),
            _delta_,
            string.concat("ltv != expected")
        );
    }

    function test__adjustLeverage_only_flashLoan() public {
        uint256 amountMint = 1e18;
        uint256 amountDeposit = 1e18;

        deal(address(sAvax), bob, amountMint);

        vm.startPrank(bob);
        sAvax.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        uint256 balance = IERC20(address(csAVAX)).balanceOf(address(strategy));
        uint256 rate = strategyContract.exchangeRate(address(csAVAX));
        uint256 expectedUnderlying = balance.mulDiv(rate, 1e18, Math.Rounding.Floor);

        // check total assets - should be lt than totalDeposits
        assertLt(strategy.totalAssets(), expectedUnderlying, "ta");

        // TODO
        // (uint256 slippageDebt, , ) = sAvaxPool.convertavaxTosAvax(
        //     cwAVAX.balanceOf(address(strategy))
        // );

        // slippageDebt = slippageDebt.mulDiv(slippage, 1e18, Math.Rounding.Ceil);

        // assertApproxEqAbs(
        //     strategy.totalAssets(),
        //     amountDeposit - slippageDebt,
        //     _delta_,
        //     string.concat("totalAssets != expected")
        // );

        // // sAvax should be in lending market
        assertEq(sAvax.balanceOf(address(strategy)), 0, "sAvax");

        // adapter should now have more sAvax aToken than before
        assertGt(csAVAX.balanceOf(address(strategy)) * 1e8, amountDeposit, "collateral");

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

    function test__adjustLeverage_flashLoan_and_avax_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(sAvax), bob, amountMint);

        vm.startPrank(bob);
        sAvax.approve(address(strategy), amountMint);
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

        // sAvax should be in lending market
        assertEq(sAvax.balanceOf(address(strategy)), 0);

        // adapter should now have more sAvax aToken than before
        assertGt(csAVAX.balanceOf(address(strategy)), amountDeposit);

        // adapter should hold debt tokens
        assertGt(cwAVAX.balanceOf(address(strategy)), 0);

        // LTV is non zero now
        assertGt(strategyContract.getLTV(), 0);

        // LTV is slightly below target, since some avax dust has been deposited as collateral
        assertGt(strategyContract.targetLTV(), strategyContract.getLTV());
    }

    function test__adjustLeverage_only_avax_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountDust = 10e18;

        deal(address(sAvax), bob, amountMint);

        vm.startPrank(bob);
        sAvax.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // SEND avax TO CONTRACT
        vm.deal(address(strategy), amountDust);

        // adjust leverage - should only trigger a dust amount deposit - no flashloans
        strategyContract.adjustLeverage();

        // check total assets - should be gt than totalDeposits
        assertGt(strategy.totalAssets(), amountDeposit);

        // sAvax should be in lending market
        assertEq(sAvax.balanceOf(address(strategy)), 0);

        // adapter should now have more sAvax aToken than before
        assertGt(csAVAX.balanceOf(address(strategy)), amountDeposit);

        // adapter should not hold debt tokens
        assertEq(cwAVAX.balanceOf(address(strategy)), 0);

        // adapter should now have 0 avax dust
        assertEq(address(strategy).balance, 0);

        // LTV is still zero
        assertEq(strategyContract.getLTV(), 0);
    }

    function test__leverageDown() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;

        deal(address(sAvax), bob, amountMint);

        vm.startPrank(bob);
        sAvax.approve(address(strategy), amountMint);
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

        deal(address(sAvax), bob, amountMint);

        vm.startPrank(bob);
        sAvax.approve(address(strategy), amountMint);
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

        // should not hold any sAvax aToken
        assertEq(csAVAX.balanceOf(address(strategy)), 0);

        // adapter should not hold debt any debt
        assertEq(cwAVAX.balanceOf(address(strategy)), 0);
    }

    function test_withdraw_dust() public {
        // manager can withdraw sAvax balance when vault total supply is 0
        deal(address(sAvax), address(strategy), 10e18);

        vm.prank(address(this));
        strategyContract.withdrawDust(address(this));

        assertEq(strategy.totalAssets(), 0, "TA");
    }

    function test_withdraw_dust_invalid() public {
        // manager can not withdraw sAvax balance when vault total supply is > 0
        deal(address(sAvax), address(bob), 10e18);

        vm.startPrank(bob);
        sAvax.approve(address(strategy), 10e18);
        strategy.deposit(10e18, bob);
        vm.stopPrank();

        uint256 totAssetsBefore = strategy.totalAssets();
        uint256 sAvaxOwnerBefore = IERC20(address(sAvax)).balanceOf(
            address(this)
        );

        vm.prank(address(this));
        strategyContract.withdrawDust(address(this));

        assertEq(strategy.totalAssets(), totAssetsBefore, "TA DUST");
        assertEq(
            IERC20(address(sAvax)).balanceOf(address(this)),
            sAvaxOwnerBefore,
            "OWNER DUST"
        );
    }

    function test__setLeverageValues_lever_up() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(sAvax), bob, amountMint);

        vm.startPrank(bob);
        sAvax.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        uint256 oldABalance = csAVAX.balanceOf(address(strategy));
        uint256 oldLTV = strategyContract.getLTV();

        strategyContract.setLeverageValues(8.5e17, 8.8e17);

        assertGt(csAVAX.balanceOf(address(strategy)), oldABalance);
        assertGt(strategyContract.getLTV(), oldLTV);
    }

    function test__setLeverageValues_lever_down() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(sAvax), bob, amountMint);

        vm.startPrank(bob);
        sAvax.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        uint256 oldABalance = csAVAX.balanceOf(address(strategy));
        uint256 oldLTV = strategyContract.getLTV();

        strategyContract.setLeverageValues(3e17, 4e17);

        assertLt(csAVAX.balanceOf(address(strategy)), oldABalance);
        assertLt(strategyContract.getLTV(), oldLTV);
    }

    function test__setLeverageValues_invalidInputs() public {
        // protocolLTV < targetLTV < maxLTV
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseCompoundV2LeverageStrategy.InvalidLTV.selector,
                3e18,
                4e18,
                strategyContract.protocolMaxLTV()
            )
        );
        strategyContract.setLeverageValues(3e18, 4e18);

        // maxLTV < targetLTV < protocolLTV
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseCompoundV2LeverageStrategy.InvalidLTV.selector,
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
                BaseCompoundV2LeverageStrategy.InvalidSlippage.selector,
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
        vm.expectRevert(BaseCompoundV2LeverageStrategy.NotFlashLoan.selector);
        vm.prank(bob);
        strategyContract.executeOperation(
            assets,
            amounts,
            premiums,
            address(strategy),
            ""
        );

        // reverts with invalid initiator and valid msg.sender
        vm.expectRevert(BaseCompoundV2LeverageStrategy.NotFlashLoan.selector);
        vm.prank(address(aaveLendingPool));
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

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public {
        assertEq(strategy.asset(), address(sAvax), "asset");
        assertEq(
            IERC20Metadata(address(strategy)).name(),
            string.concat(
                "VaultCraft Compound Leveraged ",
                IERC20Metadata(address(sAvax)).name(),
                " Strategy"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(strategy)).symbol(),
            string.concat("vc-", IERC20Metadata(address(sAvax)).symbol()),
            "symbol"
        );

        assertApproxEqAbs(
            wAVAX.allowance(address(strategy), address(aaveLendingPool)),
            type(uint256).max,
            1,
            "allowance"
        );

        assertApproxEqAbs(
            sAvax.allowance(address(strategy), address(csAVAX)),
            type(uint256).max,
            1,
            "allowance"
        );
    }
}
