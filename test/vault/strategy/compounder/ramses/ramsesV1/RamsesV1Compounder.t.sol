// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {RamsesV1Adapter, SafeERC20, IERC20, IERC20Metadata, Math, IGauge, ILpToken} from "../../../../../../src/vault/adapter/ramses/ramsesV1/RamsesV1Adapter.sol";
import {RamsesV1Compounder} from "../../../../../../src/vault/strategy/compounder/ramses/ramsesV1/RamsesV1Compounder.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

contract RamsesLpCompounderTest is Test {
    address _gauge = address(0x148Ca200d452AD9F310501ca3fd5C3bD4a5aBe81);
    address ramsesRouter = address(0xAAA87963EFeB6f7E0a2711F397663105Acb1805e);
    address uniRouter = address(0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD);
    address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address frxeth = address(0x178412e79c25968a32e89b11f63B33F733770c2A);

    RamsesV1Adapter adapter;

    IGauge gauge;
    ILpToken lpToken;
    address lpToken0;
    address lpToken1;
    address ram;
    address asset;

    bytes4[8] sigs;
    bytes[] toBaseAssetPaths;
    bytes[] toAssetPaths;
    uint256[] minTradeAmounts;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("arbitrum"));
        vm.selectFork(forkId);

        IGauge gauge = IGauge(_gauge);
        asset = gauge.stake();
        lpToken = ILpToken(asset);
        ram = gauge.rewards(0);
        lpToken0 = lpToken.token0();
        lpToken1 = lpToken.token1();

        toBaseAssetPaths.push(abi.encodePacked(ram, uint24(3000), weth));

        toAssetPaths.push(abi.encodePacked(weth, uint24(3000), frxeth));

        minTradeAmounts.push(uint256(1));

        bytes memory stratData = abi.encode(
            weth,
            ramsesRouter,
            uniRouter,
            toBaseAssetPaths,
            toAssetPaths,
            minTradeAmounts,
            abi.encode("")
        );

        address impl = address(new RamsesV1Adapter());

        adapter = RamsesV1Adapter(Clones.clone(impl));

        adapter.initialize(
            abi.encode(
                asset,
                address(this),
                new RamsesV1Compounder(),
                0,
                sigs,
                stratData
            ),
            address(gauge),
            abi.encode(address(gauge))
        );
    }

    function test__init() public {
        assertEq(
            IERC20(address(ram)).allowance(
                address(adapter),
                address(uniRouter)
            ),
            type(uint256).max
        );

        assertEq(
            IERC20(address(lpToken0)).allowance(
                address(adapter),
                address(ramsesRouter)
            ),
            type(uint256).max
        );

        assertEq(
            IERC20(address(lpToken0)).allowance(
                address(adapter),
                address(uniRouter)
            ),
            type(uint256).max
        );

        assertEq(
            IERC20(address(lpToken1)).allowance(
                address(adapter),
                address(ramsesRouter)
            ),
            type(uint256).max
        );

        assertEq(
            IERC20(address(lpToken1)).allowance(
                address(adapter),
                address(uniRouter)
            ),
            type(uint256).max
        );
    }

    function test__compound() public {
        deal(address(lpToken), address(this), 1e18);
        IERC20(address(lpToken)).approve(address(adapter), type(uint256).max);
        adapter.deposit(1e18, address(this));

        uint256 oldTa = adapter.totalAssets();

        vm.roll(block.number + 10_000);
        vm.warp(block.timestamp + 150_000);

        adapter.harvest();

        assertGt(adapter.totalAssets(), oldTa);
    }
}
