// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test, console} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {PushOracle, Errors, Scale} from "src/peripheral/oracles/adapter/pushOracle/PushOracle.sol";
import {PushOracleOwner} from "src/peripheral/oracles/adapter/pushOracle/PushOracleOwner.sol";

contract PushOracleTest is Test {
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    PushOracleOwner oracleOwner;
    PushOracle oracle;

    address public bob = address(0x9999);
    address public alice = address(0x8888);

    event PriceUpdated(
        address base,
        address quote,
        uint256 bqPrice,
        uint256 qbPrice
    );

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        oracle = new PushOracle(address(this));
        oracleOwner = new PushOracleOwner(address(oracle), address(this));

        oracle.nominateNewOwner(address(oracleOwner));
        oracleOwner.acceptOracleOwnership();
    }

    /*//////////////////////////////////////////////////////////////
                            SET PRICE
    //////////////////////////////////////////////////////////////*/

    function test__setPrice() public {
        vm.expectEmit(true, true, false, true);
        emit PriceUpdated(weth, usdc, 2500e18, 2.5e15);
        oracleOwner.setPrice(weth, usdc, 2500e18, 2.5e15);

        assertEq(oracle.prices(weth, usdc), 2500e18);
        assertEq(oracle.prices(usdc, weth), 2.5e15);
    }

    function test__setPrice_keeper() public {
        oracleOwner.setKeeper(bob);

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit PriceUpdated(weth, usdc, 2500e18, 2.5e15);
        oracleOwner.setPrice(weth, usdc, 2500e18, 2.5e15);

        assertEq(oracle.prices(weth, usdc), 2500e18);
        assertEq(oracle.prices(usdc, weth), 2.5e15);
    }

    function test__setPrice_fails_if_none_owner() public {
        vm.startPrank(bob);
        vm.expectRevert(PushOracleOwner.NotKeeperNorOwner.selector);
        oracleOwner.setPrice(weth, usdc, 2500e18, 2.5e15);
    }

    function test__setPrice_fails_if_none_keeper() public {
        oracleOwner.setKeeper(bob);

        vm.startPrank(alice);
        vm.expectRevert(PushOracleOwner.NotKeeperNorOwner.selector);
        oracleOwner.setPrice(weth, usdc, 2500e18, 2.5e15);
    }

    function test__setPrice_fails_if_one_price_zero() public {
        vm.expectRevert(PushOracle.Misconfigured.selector);
        oracleOwner.setPrice(weth, usdc, 2500e18, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            GET PRICE
    //////////////////////////////////////////////////////////////*/

    function test__getPrice() public {
        oracleOwner.setPrice(weth, usdc, 2500e18, 2.5e15);

        assertEq(oracle.getQuote(1e18, weth, usdc), 2500e6);
        assertEq(oracle.getQuote(1e6, usdc, weth), 2.5e15);
    }

    function test__getPrice_fails_if_price_zero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PriceOracle_NotSupported.selector,
                weth,
                usdc
            )
        );
        oracle.getQuote(1e18, weth, usdc);
    }
}
