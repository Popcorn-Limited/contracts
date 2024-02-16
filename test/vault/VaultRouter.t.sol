// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ICurveGauge} from "../../src/interfaces/external/curve/ICurveGauge.sol";
import {VaultRouter} from "../../src/vault/VaultRouter.sol";

contract VaultRouterTest is Test {
    address bob = address(0x08fD119453cD459F7E9e4232AD9816266863BFb1); // testing account on goerli

    IERC20 asset;
    IERC4626 vault;
    ICurveGauge gauge;

    VaultRouter router;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("goerli"), 9612570);
        vm.selectFork(forkId);

        asset = IERC20(0xba383A6649a8C849fc9274181D7B077D2b84FA95);
        vault = IERC4626(0xb7C628257065F295519a85dD35fD04014f4A8B17);
        gauge = ICurveGauge(0x6351a986f4BA341C2649026B467e75C4C434B000);

        router = new VaultRouter();

        vm.startPrank(bob);
    }

    function test__depositAndStake() public {
        uint256 assetAmount = 1e18;

        uint256 oldBal = IERC20(address(gauge)).balanceOf(bob);

        asset.approve(address(router), assetAmount);

        router.depositAndStake(vault, gauge, assetAmount, bob);

        assertEq(IERC20(address(gauge)).balanceOf(bob), oldBal + 1e27);
    }

    function test__unstakeAndWithdraw() public {
        uint256 redeemAmount = 1e27;

        uint256 oldBal = asset.balanceOf(bob);

        IERC20(address(gauge)).approve(address(router), redeemAmount);

        router.unstakeAndWithdraw(vault, gauge, redeemAmount, bob);

        assertEq(asset.balanceOf(bob), oldBal + 1e18);
    }
}
