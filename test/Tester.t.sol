// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test, console} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

interface IVe {
    function increase_amount(uint256 amount) external;
}

interface IVaultRouter {
    function depositAndStake(
        address vault,
        address gauge,
        uint256 assetAmount,
        address receiver
    ) external;

    function unstakeAndWithdraw(
        address vault,
        address gauge,
        uint256 burnAmount,
        address receiver
    ) external;
}

contract Tester is Test {
    address router = 0x48943F145686bF5c4580D545CDA405844D1f777b;
    address gauge = 0xc9aD14cefb29506534a973F7E0E97e68eCe4fa3f;
    address assetAddr = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address vaultAddr = 0xD3A17928245064B6DF5095a76e277fe441D538a4;

    IERC20 asset = IERC20(assetAddr);
    IERC4626 vault = IERC4626(vaultAddr);

    address alice = address(0xABCD);
    address bob = address(0xDCBA);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum"));
    }

    function testA() public {
        _testFullWithdraw(0x8864FcD125E24d3cF52AAc71d0EDc61922566740);
        _testFullWithdraw(0x8e130dAB21241dB653BfAD148ADF7887A84c7Ec3);
        _testFullWithdraw(0x0F833bceE52faE0Cf75574d11d327280dF69d21c);
        _testFullWithdraw(0xA5aEf04E03789AD15405D153a82D0b128c36988b);
        _testFullWithdraw(0x1529c4A1682b71FadA517d1BD7Fed68A439F9bdE);

        _testFullWithdraw(0x72566F5A58182A3Dedba2b39508787de819C757f);
        _testFullWithdraw(0x84f40ebac4C7a5216f5f0c64b96a169834058eBC);
        _testFullWithdraw(0x3B62E21a4050E19cD6B65aeC10b8373720D53b90);
        _testFullWithdraw(0xEb4A99A64651247a279C6fe20876D10F9b3D869D);
        _testFullWithdraw(0x18572624dae48120248A50C6e6Aa12E4ed41cf4F);

        _testFullWithdraw(0x3ADB6778474937bCb9C6befC59Cb7952f8cBa05f);
        _testFullWithdraw(0x80C2683506f852b3bf9cb0D6A0948D89e760dE80);
        _testFullWithdraw(0x14198F196897837c62Ce82298Ea1460B05A4f39c);
        _testFullWithdraw(0xB8C59E56CaFB784D63705bFdC4cD7746098C66A2);
        _testFullWithdraw(0xE8C88ed63204452d3663bDa37A3832a227FDb90c);

        _testFullWithdraw(0x1c47963f1A58eB763965e8AC984495a30e8A48ed);
        _testFullWithdraw(0xCe933D37829aDe30c24E77923cE15fF73e029Ec5);
        _testFullWithdraw(0x00847Cfd35A6d0Ce37530d62E5a78D1e333A2068);
        _testFullWithdraw(0xAE889351428ceb16A7517187616FDA9273fF7CD7);
        _testFullWithdraw(0xECf9b65f32653b77439617Bd8a7D6AeB261e5661);

        _testFullWithdraw(0xc0aDAb663C980180E19fa8D4Ad9F504840c6e20D);
        _testFullWithdraw(0xDf6f6E4493246dE78315831BFcAF9fb92d4E4629);
        _testFullWithdraw(0xc0Fa5fD1C9CE8c38d48Df3548b36fdDd21BB66e5);
    }

    function _testFullWithdraw(address user) internal {
        vm.startPrank(user, user);
        uint256 gaugeBal = IERC20(gauge).balanceOf(user);
        IERC20(gauge).approve(router, gaugeBal);
        IVaultRouter(router).unstakeAndWithdraw(
            vaultAddr,
            gauge,
            gaugeBal,
            user
        );
        vm.stopPrank();
    }

    function test__deposit_withdraw(uint128 depositAmount) public {
        uint amount = bound(uint(depositAmount), 1, 100_000e18);

        deal(address(asset), alice, amount);

        vm.prank(alice);
        asset.approve(address(vault), amount);
        assertEq(asset.allowance(alice, address(vault)), amount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        assertEq(amount, shares);
        assertApproxEqAbs(
            vault.previewWithdraw(amount),
            shares,
            10,
            "previewWithdraw should match share amount"
        );
        assertApproxEqAbs(
            vault.previewDeposit(amount),
            shares,
            10,
            "previewDeposit should match share amount"
        );
        assertApproxEqAbs(
            vault.totalSupply(),
            shares,
            10,
            "totalSupply should be equal to minted shares"
        );
        assertApproxEqAbs(
            vault.totalAssets(),
            amount,
            10,
            "totalAssets should be equal to deposited amount"
        );
        assertApproxEqAbs(
            vault.balanceOf(alice),
            shares,
            10,
            "alice should own all the minted vault shares"
        );
        assertApproxEqAbs(
            vault.convertToAssets(vault.balanceOf(alice)),
            amount,
            10,
            "minted shares should be convertable to deposited amount of assets"
        );
        assertApproxEqAbs(
            asset.balanceOf(alice),
            alicePreDepositBal - amount,
            10,
            "should have transferred assets from alice to vault"
        );

        uint withdrawAmount = vault.maxWithdraw(alice);
        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertApproxEqAbs(
            asset.balanceOf(alice),
            alicePreDepositBal,
            10,
            "should should have same amount of assets after withdrawal"
        );
    }
    function test__mint_redeem() public {
        uint amount = 1e18;
        amount = bound(amount, 1, 100_000e18);

        deal(address(asset), alice, amount);

        vm.prank(alice);
        asset.approve(address(vault), amount);
        assertEq(asset.allowance(alice, address(vault)), amount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceAssetAmount = vault.mint(amount, alice);

        // Expect exchange rate to be 1:1 on initial mint.
        assertApproxEqAbs(amount, aliceAssetAmount, 1, "share = assets");
        assertApproxEqAbs(
            vault.previewWithdraw(aliceAssetAmount),
            amount,
            1,
            "pw"
        );
        assertApproxEqAbs(
            vault.previewDeposit(aliceAssetAmount),
            amount,
            1,
            "pd"
        );
        assertEq(vault.totalSupply(), amount, "ts");
        assertApproxEqAbs(vault.totalAssets(), aliceAssetAmount, 10, "ta");
        assertEq(vault.balanceOf(alice), amount, "bal");
        assertApproxEqAbs(
            vault.convertToAssets(vault.balanceOf(alice)),
            aliceAssetAmount,
            1,
            "convert"
        );
        assertEq(
            asset.balanceOf(alice),
            alicePreDepositBal - aliceAssetAmount,
            "a bal"
        );

        uint redeemAmount = vault.maxRedeem(alice);
        vm.prank(alice);
        vault.redeem(redeemAmount, alice, alice);

        assertApproxEqAbs(vault.totalAssets(), 0, 1);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertApproxEqAbs(asset.balanceOf(alice), alicePreDepositBal, 1);
    }
    function test__interactions_for_someone_else() public {
        // init 2 users with a 1e18 balance
        deal(address(asset), alice, 1e18);
        deal(address(asset), bob, 1e18);

        vm.prank(alice);
        asset.approve(address(vault), 1e18);

        vm.prank(bob);
        asset.approve(address(vault), 1e18);

        // alice deposits 1e18 for bob
        vm.prank(alice);
        vault.deposit(1e18, bob);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), 1e18);
        assertEq(asset.balanceOf(alice), 0);

        // bob mint 1e18 for alice
        vm.prank(bob);
        vault.mint(1e18, alice);
        assertEq(vault.balanceOf(alice), 1e18);
        assertEq(vault.balanceOf(bob), 1e18);
        assertEq(asset.balanceOf(bob), 0);

        // alice redeem 1e18 for bob
        vm.prank(alice);
        vault.redeem(1e18, bob, alice);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), 1e18);
        assertApproxEqAbs(asset.balanceOf(bob), 1e18, 10);

        // bob withdraw 1e18 for alice
        vm.prank(bob);
        vault.withdraw(1e18, alice, bob);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), 0);
        assertApproxEqAbs(asset.balanceOf(alice), 1e18, 10);
    }
}
