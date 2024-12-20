// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {VaultRouter} from "src/utils/VaultRouter.sol";
import {MockERC20, ERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";
import {MockGauge} from "test/mocks/MockGauge.sol";

contract VaultRouterTest is Test {
    VaultRouter public router;
    MockERC20 public asset;
    MockERC4626 public vault;
    MockGauge public gauge;
    address public user = address(0x1);

    function setUp() public {
        router = new VaultRouter();
        asset = new MockERC20("Test Asset", "TAST", 18);
        vault = new MockERC4626();
        vault.initialize(asset, "Test Vault", "vTAST");
        gauge = new MockGauge(address(vault));

        // Mint some assets to the user
        asset.mint(user, 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                            SYNC FLOW
    //////////////////////////////////////////////////////////////*/

    function test__depositAndStake() public {
        uint256 amount = 100e18;
        uint256 minOut = 99e18; // Assuming 1% max slippage

        vm.startPrank(user);
        asset.approve(address(router), amount);
        router.depositAndStake(
            address(vault),
            address(gauge),
            amount,
            minOut,
            user
        );
        vm.stopPrank();

        assertEq(gauge.balanceOf(user), amount);
        assertEq(asset.balanceOf(user), 0);
    }

    function test__unstakeAndWithdraw() public {
        // First, deposit and stake
        test__depositAndStake();

        uint256 amount = 100e18;
        uint256 minOut = 99e18; // Assuming 1% max slippage

        vm.startPrank(user);
        gauge.approve(address(router), amount);
        router.unstakeAndWithdraw(
            address(vault),
            address(gauge),
            amount,
            minOut,
            user
        );
        vm.stopPrank();

        assertEq(gauge.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), 100e18);
    }

    function test__slippageProtection_depositAndStake() public {
        uint256 amount = 100e18;
        uint256 minOut = 101e18; // Set minOut higher than possible output

        vm.startPrank(user);
        asset.approve(address(router), amount);
        vm.expectRevert(VaultRouter.SlippageTooHigh.selector);
        router.depositAndStake(
            address(vault),
            address(gauge),
            amount,
            minOut,
            user
        );
        vm.stopPrank();
    }

    function test__slippageProtection_unstakeAndWithdraw() public {
        // First, deposit and stake
        test__depositAndStake();

        uint256 amount = 100e18;
        uint256 minOut = 101e18; // Set minOut higher than possible output

        vm.startPrank(user);
        gauge.approve(address(router), amount);
        vm.expectRevert(VaultRouter.SlippageTooHigh.selector);
        router.unstakeAndWithdraw(
            address(vault),
            address(gauge),
            amount,
            minOut,
            user
        );
        vm.stopPrank();
    }
}
