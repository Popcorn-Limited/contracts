// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {stdJson} from "forge-std/StdJson.sol";

import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/interfaces/IERC20Metadata.sol";

import {IBaseStrategy} from "../../src/interfaces/IBaseStrategy.sol";
import {PropertyTest, TestConfig} from "./PropertyTest.prop.sol";

abstract contract BaseStrategyTest is PropertyTest {
    using Math for uint256;
    using stdJson for string;

    string internal path;
    string internal fullPath;
    string internal json;

    TestConfig internal testConfig;

    IBaseStrategy public strategy;

    address public bob = address(0x9999);
    address public alice = address(0x8888);

    function _setUpBaseTest(uint256 configIndex, string memory path_) internal virtual {
        // Read test config
        path = path_;
        fullPath = string.concat(vm.projectRoot(), path_);
        json = vm.readFile(path);

        testConfig =
            abi.decode(json.parseRaw(string.concat(".configs[", vm.toString(configIndex), "].base")), (TestConfig));

        // Setup fork environment
        testConfig.blockNumber > 0
            ? vm.createSelectFork(vm.rpcUrl(testConfig.network), testConfig.blockNumber)
            : vm.createSelectFork(vm.rpcUrl(testConfig.network));

        // Setup strategy
        strategy = _setUpStrategy(json, vm.toString(configIndex), testConfig);

        // Setup PropertyTest
        _vault_ = address(strategy);
        _asset_ = testConfig.asset;
        _delta_ = testConfig.delta;

        // Labelling
        vm.label(bob, "bob");
        vm.label(alice, "alice");
        vm.label(address(this), "owner");
        vm.label(address(strategy), "strategy");
        vm.label(testConfig.asset, "asset");
    }

    /*//////////////////////////////////////////////////////////////
                                HELPER
    //////////////////////////////////////////////////////////////*/

    /// @dev -- This MUST be overriden to setup a strategy
    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        virtual
        returns (IBaseStrategy);

    function _mintAsset(uint256 amount, address receiver) internal virtual {
        // USDC on mainnet cant be dealt (find(StdStorage): Slot(s) not found) therefore we transfer from a whale
        if (block.chainid == 1 && testConfig.asset == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) {
            vm.prank(0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa);
            IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).transfer(receiver, amount);
        } else {
            deal(testConfig.asset, receiver, amount);
        }
    }

    function _mintAssetAndApproveForStrategy(uint256 amount, address receiver) internal virtual {
        _mintAsset(amount, receiver);

        vm.prank(receiver);
        IERC20(testConfig.asset).approve(address(strategy), amount);
    }

    function _increasePricePerShare(uint256 amount) internal virtual {}

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /*
     * @dev This function checks that the invariants in the strategy initialization function are checked:
     *      Some of the invariants that could be checked:
     *      - check that all errors in the strategy init function revert.
     *      - specific protocol or strategy config are verified in the registry.
     *      - correct allowance amounts are approved
     */
    function test__initialization() public virtual {
        assertEq(strategy.asset(), testConfig.asset);
        assertEq(strategy.decimals(), IERC20Metadata(testConfig.asset).decimals());
    }

    /*//////////////////////////////////////////////////////////////
                          TOTAL ASSETS
    //////////////////////////////////////////////////////////////*/

    /// @dev - This MUST be overriden to test that totalAssets adds up the the expected values
    function test__totalAssets() public virtual {}

    /*//////////////////////////////////////////////////////////////
                          CONVERSION VIEWS
    //////////////////////////////////////////////////////////////*/

    function test__convertToShares() public virtual {
        prop_convertToShares(bob, alice, testConfig.defaultAmount);
    }

    function test__convertToAssets() public virtual {
        prop_convertToAssets(bob, alice, testConfig.defaultAmount);
    }

    /*//////////////////////////////////////////////////////////////
                          MAX VIEWS
    //////////////////////////////////////////////////////////////*/

    /// NOTE: These Are just prop tests currently. Override tests here if the strategy has unique max-functions which override BaseStrategy.sol
    function test__maxDeposit() public virtual {
        assertEq(strategy.maxDeposit(bob), type(uint256).max);

        // We need to deposit smth since pause tries to burn rETH which it cant if balance is 0
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);
        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        vm.prank(address(this));
        strategy.pause();

        assertEq(strategy.maxDeposit(bob), 0);
    }

    function test__maxMint() public virtual {
        assertEq(strategy.maxMint(bob), type(uint256).max);

        // We need to deposit smth since pause tries to burn rETH which it cant if balance is 0
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);
        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        vm.prank(address(this));
        strategy.pause();

        assertEq(strategy.maxMint(bob), 0);
    }

    function test__maxWithdraw() public virtual {
        prop_maxWithdraw(bob);
    }

    function test__maxRedeem() public virtual {
        prop_maxRedeem(bob);
    }

    /*//////////////////////////////////////////////////////////////
                          PREVIEW VIEWS
    //////////////////////////////////////////////////////////////*/

    function test__previewDeposit(uint8 fuzzAmount) public virtual {
        uint256 amount = bound(fuzzAmount, testConfig.minDeposit, testConfig.maxDeposit);

        _mintAsset(amount, bob);
        vm.prank(bob);

        IERC20(testConfig.asset).approve(address(strategy), amount);

        prop_previewDeposit(bob, bob, amount, testConfig.testId);
    }

    function test__previewMint(uint8 fuzzAmount) public virtual {
        uint256 amount = bound(fuzzAmount, testConfig.minDeposit, testConfig.maxDeposit);

        uint256 reqAssets = strategy.previewMint(amount);
        _mintAsset(reqAssets, bob);

        vm.prank(bob);
        IERC20(testConfig.asset).approve(address(strategy), reqAssets);

        prop_previewMint(bob, bob, amount, testConfig.testId);
    }

    function test__previewWithdraw(uint8 fuzzAmount) public virtual {
        uint256 amount = bound(fuzzAmount, testConfig.minDeposit, testConfig.maxDeposit);

        /// Some strategies have slippage or rounding errors which makes `maWithdraw` lower than the deposit amount
        uint256 reqAssets = strategy.previewMint(strategy.previewWithdraw(amount)) + 10;

        _mintAssetAndApproveForStrategy(reqAssets, bob);

        vm.prank(bob);
        strategy.deposit(reqAssets, bob);

        prop_previewWithdraw(bob, bob, bob, amount, testConfig.testId);
    }

    function test__previewRedeem(uint8 fuzzAmount) public virtual {
        uint256 amount = bound(fuzzAmount, testConfig.minDeposit, testConfig.maxDeposit);

        uint256 reqAssets = strategy.previewMint(strategy.previewRedeem(amount));
        _mintAssetAndApproveForStrategy(reqAssets, bob);

        vm.prank(bob);
        strategy.deposit(reqAssets, bob);

        prop_previewRedeem(bob, bob, bob, amount, testConfig.testId);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/MINT/WITHDRAW/REDEEM
    //////////////////////////////////////////////////////////////*/

    function test__deposit(uint8 fuzzAmount) public virtual {
        uint256 len = json.readUint(".length");
        for (uint256 i; i < len; i++) {
            if (i > 0) _setUpBaseTest(i, path);

            uint256 amount = bound(fuzzAmount, testConfig.minDeposit, testConfig.maxDeposit);

            _mintAssetAndApproveForStrategy(amount, bob);

            prop_deposit(bob, bob, amount, testConfig.testId);

            _increasePricePerShare(testConfig.defaultAmount);

            _mintAssetAndApproveForStrategy(amount, bob);
            prop_deposit(bob, alice, amount, testConfig.testId);
        }
    }

    function testFail__deposit_zero() public {
        strategy.deposit(0, address(this));
    }

    function test__mint(uint8 fuzzAmount) public virtual {
        uint256 len = json.readUint(".length");
        for (uint256 i; i < len; i++) {
            if (i > 0) _setUpBaseTest(i, path);

            uint256 amount = bound(fuzzAmount, testConfig.minDeposit, testConfig.maxDeposit);

            _mintAssetAndApproveForStrategy(strategy.previewMint(amount), bob);

            prop_mint(bob, bob, amount, testConfig.testId);

            _increasePricePerShare(testConfig.defaultAmount);

            _mintAssetAndApproveForStrategy(strategy.previewMint(amount), bob);

            prop_mint(bob, alice, amount, testConfig.testId);
        }
    }

    function testFail__mint_zero() public {
        strategy.mint(0, address(this));
    }

    function test__withdraw(uint8 fuzzAmount) public virtual {
        uint256 len = json.readUint(".length");
        for (uint256 i; i < len; i++) {
            if (i > 0) _setUpBaseTest(i, path);

            uint256 amount = bound(fuzzAmount, testConfig.minDeposit, testConfig.maxDeposit);

            uint256 reqAssets = strategy.previewMint(strategy.previewWithdraw(amount));
            _mintAssetAndApproveForStrategy(reqAssets, bob);
            vm.prank(bob);
            strategy.deposit(reqAssets, bob);

            prop_withdraw(bob, bob, strategy.maxWithdraw(bob), testConfig.testId);

            _mintAssetAndApproveForStrategy(reqAssets, bob);
            vm.prank(bob);
            strategy.deposit(reqAssets, bob);

            _increasePricePerShare(testConfig.defaultAmount);

            vm.prank(bob);
            strategy.approve(alice, type(uint256).max);

            prop_withdraw(alice, bob, strategy.maxWithdraw(bob), testConfig.testId);
        }
    }

    function testFail__withdraw_zero() public {
        strategy.withdraw(0, address(this), address(this));
    }

    function test__redeem(uint8 fuzzAmount) public virtual {
        uint256 len = json.readUint(".length");
        for (uint256 i; i < len; i++) {
            if (i > 0) _setUpBaseTest(i, path);

            uint256 amount = bound(fuzzAmount, testConfig.minDeposit, testConfig.maxDeposit);

            uint256 reqAssets = strategy.previewMint(amount);
            _mintAssetAndApproveForStrategy(reqAssets, bob);

            vm.prank(bob);
            strategy.deposit(reqAssets, bob);
            prop_redeem(bob, bob, strategy.maxRedeem(bob), testConfig.testId);

            _mintAssetAndApproveForStrategy(reqAssets, bob);
            vm.prank(bob);
            strategy.deposit(reqAssets, bob);

            _increasePricePerShare(testConfig.defaultAmount);

            vm.prank(bob);
            strategy.approve(alice, type(uint256).max);
            prop_redeem(alice, bob, strategy.maxRedeem(bob), testConfig.testId);
        }
    }

    function testFail__redeem_zero() public {
        strategy.redeem(0, address(this), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test__RT_deposit_redeem() public virtual {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.startPrank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);
        uint256 assets = strategy.redeem(strategy.maxRedeem(bob), bob, bob);
        vm.stopPrank();

        // Pass the test if maxRedeem is smaller than deposit since round trips are impossible
        if (strategy.maxRedeem(bob) == testConfig.defaultAmount) {
            assertLe(assets, testConfig.defaultAmount, testConfig.testId);
        }
    }

    function test__RT_deposit_withdraw() public virtual {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.startPrank(bob);
        uint256 shares1 = strategy.deposit(testConfig.defaultAmount, bob);
        uint256 shares2 = strategy.withdraw(strategy.maxWithdraw(bob), bob, bob);
        vm.stopPrank();

        // Pass the test if maxWithdraw is smaller than deposit since round trips are impossible
        if (strategy.maxWithdraw(bob) == testConfig.defaultAmount) {
            assertGe(shares2, shares1, testConfig.testId);
        }
    }

    function test__RT_mint_withdraw() public virtual {
        _mintAssetAndApproveForStrategy(strategy.previewMint(testConfig.minDeposit), bob);

        vm.startPrank(bob);
        uint256 assets = strategy.mint(testConfig.minDeposit, bob);
        uint256 shares = strategy.withdraw(strategy.maxWithdraw(bob), bob, bob);
        vm.stopPrank();

        if (strategy.maxWithdraw(bob) == assets) {
            assertGe(shares, testConfig.minDeposit, testConfig.testId);
        }
    }

    function test__RT_mint_redeem() public virtual {
        _mintAssetAndApproveForStrategy(strategy.previewMint(testConfig.minDeposit), bob);

        vm.startPrank(bob);
        uint256 assets1 = strategy.mint(testConfig.minDeposit, bob);
        uint256 assets2 = strategy.redeem(strategy.maxRedeem(bob), bob, bob);
        vm.stopPrank();

        if (strategy.maxRedeem(bob) == testConfig.minDeposit) {
            assertLe(assets2, assets1, testConfig.testId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            AUTODEPOSIT
    //////////////////////////////////////////////////////////////*/

    function test__toggleAutoDeposit() public virtual {
        bool prevAutoDeposit = strategy.autoDeposit();
        assertTrue(prevAutoDeposit);

        strategy.toggleAutoDeposit();

        assertEq(strategy.autoDeposit(), false);
    }

    function testFail__toggleAutoDeposit_nonOwner() public virtual {
        vm.prank(alice);
        strategy.toggleAutoDeposit();
    }

    function test__deposit_autoDeposit_off() public virtual {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        assertEq(strategy.totalAssets(), testConfig.defaultAmount, "ta");
        assertEq(strategy.totalSupply(), testConfig.defaultAmount, "ts");
        assertEq(strategy.balanceOf(bob), testConfig.defaultAmount, "share bal");
        assertEq(IERC20(_asset_).balanceOf(address(strategy)), testConfig.defaultAmount, "strategy asset bal");
    }

    function test__mint_autoDeposit_off() public virtual {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        assertEq(strategy.totalAssets(), testConfig.defaultAmount, "ta");
        assertEq(strategy.totalSupply(), testConfig.defaultAmount, "ts");
        assertEq(strategy.balanceOf(bob), testConfig.defaultAmount, "share bal");
        assertEq(IERC20(_asset_).balanceOf(address(strategy)), testConfig.defaultAmount, "strategy asset bal");
    }

    function test__withdraw_autoDeposit_off() public virtual {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.startPrank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        strategy.withdraw(strategy.previewRedeem(strategy.balanceOf(bob)), bob, bob);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), 0, "ta");
        assertEq(strategy.totalSupply(), 0, "ts");
        assertEq(strategy.balanceOf(bob), 0, "share bal");
        assertEq(IERC20(_asset_).balanceOf(bob), testConfig.defaultAmount, "asset bal");
        assertEq(IERC20(_asset_).balanceOf(address(strategy)), 0, "strategy asset bal");
    }

    function test__redeem_autoDeposit_off() public virtual {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.startPrank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        strategy.redeem(strategy.balanceOf(bob), bob, bob);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), 0, "ta");
        assertEq(strategy.totalSupply(), 0, "ts");
        assertEq(strategy.balanceOf(bob), 0, "share bal");
        assertEq(IERC20(_asset_).balanceOf(bob), testConfig.defaultAmount, "asset bal");
        assertEq(IERC20(_asset_).balanceOf(address(strategy)), 0, "strategy asset bal");
    }

    /// @dev Partially withdraw assets directly from strategy and the underlying protocol
    function test__withdraw_autoDeposit_partial() public virtual {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        // Push 40% the funds into the underlying protocol
        strategy.pushFunds((testConfig.defaultAmount / 5) * 2, bytes(""));

        // Withdraw 80% of deposit
        vm.prank(bob);
        strategy.withdraw((testConfig.defaultAmount / 5) * 4, bob, bob);

        assertApproxEqAbs(strategy.totalAssets(), testConfig.defaultAmount / 5, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), testConfig.defaultAmount / 5, _delta_, "ts");
        assertApproxEqAbs(strategy.balanceOf(bob), testConfig.defaultAmount / 5, _delta_, "share bal");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(bob), (testConfig.defaultAmount / 5) * 4, _delta_, "asset bal");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(address(strategy)), 0, _delta_, "strategy asset bal");
    }

    /// @dev Partially redeem assets directly from strategy and the underlying protocol
    function test__redeem_autoDeposit_partial() public virtual {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        // Push 40% the funds into the underlying protocol
        strategy.pushFunds((testConfig.defaultAmount / 5) * 2, bytes(""));

        // Redeem 80% of deposit
        vm.prank(bob);
        strategy.redeem((testConfig.defaultAmount / 5) * 4, bob, bob);

        assertApproxEqAbs(strategy.totalAssets(), testConfig.defaultAmount / 5, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), testConfig.defaultAmount / 5, _delta_, "ts");
        assertApproxEqAbs(strategy.balanceOf(bob), testConfig.defaultAmount / 5, _delta_, "share bal");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(bob), (testConfig.defaultAmount / 5) * 4, _delta_, "asset bal");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(address(strategy)), 0, _delta_, "strategy asset bal");
    }

    /*//////////////////////////////////////////////////////////////
                            PUSH/PULL FUNDS
    //////////////////////////////////////////////////////////////*/

    function test__pushFunds() public virtual {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        uint256 oldTa = strategy.totalAssets();
        uint256 oldTs = strategy.totalSupply();

        strategy.pushFunds(testConfig.defaultAmount, bytes(""));

        assertApproxEqAbs(strategy.totalAssets(), oldTa, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(address(strategy)), 0, _delta_, "strategy asset bal");
    }

    function testFail__pushFunds_nonOwnerNorKeeper() public virtual {
        vm.prank(alice);
        strategy.pushFunds(uint256(1e18), bytes(""));
    }

    function test__pullFunds() public virtual {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        uint256 oldTa = strategy.totalAssets();
        uint256 oldTs = strategy.totalSupply();

        strategy.pullFunds(oldTa, bytes(""));

        assertApproxEqAbs(strategy.totalAssets(), oldTa, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(address(strategy)), testConfig.defaultAmount, _delta_, "strategy asset bal"
        );
    }

    function testFail__pullFunds_nonOwnerNorKeeper() public virtual {
        vm.prank(alice);
        strategy.pullFunds(uint256(1e18), bytes(""));
    }

    /*//////////////////////////////////////////////////////////////
                            HARVEST
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public virtual {}

    function testFail__harvest_nonOwnerNorKeeper() public virtual {
        vm.prank(alice);
        strategy.harvest(bytes(""));
    }

    /*//////////////////////////////////////////////////////////////
                            KEEPER
    //////////////////////////////////////////////////////////////*/

    function test__setKeeper() public virtual {
        strategy.setKeeper(bob);

        assertEq(strategy.keeper(), bob);
    }

    function testFail__setKeeper_nonOwner() public virtual {
        vm.prank(alice);
        strategy.setKeeper(alice);
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSING
    //////////////////////////////////////////////////////////////*/

    function test__pause() public virtual {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        uint256 oldTotalAssets = strategy.totalAssets();

        vm.prank(address(this));
        strategy.pause();

        // We simply withdraw into the strategy
        // TotalSupply and Assets dont change
        assertApproxEqAbs(oldTotalAssets, strategy.totalAssets(), testConfig.delta, "totalAssets");
    }

    function testFail__pause_nonOwner() public virtual {
        vm.prank(alice);
        strategy.pause();
    }

    function test__unpause() public virtual {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount * 3, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount * 3, bob);

        uint256 oldTotalAssets = strategy.totalAssets();

        vm.prank(address(this));
        strategy.pause();

        vm.prank(address(this));
        strategy.unpause();

        // We simply deposit back into the external protocol
        // TotalAssets shouldnt change significantly besides some slippage or rounding errors
        assertApproxEqAbs(oldTotalAssets, strategy.totalAssets(), testConfig.delta * 3, "totalAssets");
        assertApproxEqAbs(IERC20(testConfig.asset).balanceOf(address(strategy)), 0, testConfig.delta, "asset balance");
    }

    function testFail__unpause_nonOwner() public virtual {
        strategy.pause();

        vm.prank(alice);
        strategy.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                              PERMIT
    //////////////////////////////////////////////////////////////*/

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function test__permit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    strategy.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(0xCAFE), 1e18, 0, block.timestamp))
                )
            )
        );

        strategy.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);

        assertEq(strategy.allowance(owner, address(0xCAFE)), 1e18, "allowance");
        assertEq(strategy.nonces(owner), 1, "nonce");
    }
}
