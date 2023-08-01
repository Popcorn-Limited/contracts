pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

import {IPool, StrategyConfig, CurveLPCompounder, CurveRoute} from "../../src/vault/v2/curve/CurveLPCompounder.sol";
import {StrategyConfig, CurveRoute} from "../../src/vault/v2/curve/CurveCompounder.sol";
import {BaseVaultInitData} from "../../src/vault/v2/BaseVault.sol";
import {VaultFees} from "../../src/interfaces/vault/IVault.sol";

contract CurveLPCompounderTest is Test {
    CurveLPCompounder vault;
    IERC20 asset;

    address alice = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address bob = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        asset = IERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);

        address minter = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;
        address gauge = 0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A;
        address pool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
        address crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
        CurveRoute[] memory curveRoutes = new CurveRoute[](1);

        address[9] memory toBaseAssetRoute = [
            crv,
            0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511, // crv / eth
            eth,
            0xD51a44d3FaE010294C616388b506AcdA1bfAAE46, // tricrypto2
            usdt,
            address(0),
            address(0),
            address(0),
            address(0) 
        ];
        uint[3][4] memory swapParams;
        swapParams[0] = [uint(1), 0, 3];
        swapParams[1] = [uint(2), 0, 3];
    
        curveRoutes[0] = CurveRoute({route: toBaseAssetRoute, swapParams: swapParams});
    
        uint[] memory minTradeAmounts = new uint[](1);
        minTradeAmounts[0] = 0;
    
        StrategyConfig memory stratConfig = StrategyConfig({
            autoHarvest: 2,
            harvestCooldown: 1 hours,
            router: 0x99a58482BD75cbab83b27EC03CA68fF489b5788f,
            baseAsset: usdt,
            toBaseAssetRoutes: curveRoutes,
            minTradeAmounts: minTradeAmounts
        });

        address impl = address(new CurveLPCompounder());
        vault = CurveLPCompounder(Clones.clone(impl)) ;
        bytes memory initData = abi.encode(
            gauge,
            minter,
            pool,
            uint8(3),
            2,
            stratConfig
        );
        BaseVaultInitData memory baseVaultInitData = BaseVaultInitData({
            asset: address(asset),
            name: "Test Vault",
            symbol: "TV",
            owner: address(this),
            fees: VaultFees(0, 0, 0, 0),
            feeRecipient: address(this),
            depositLimit: type(uint).max
        });

        vault.initialize(baseVaultInitData, initData);
    
        vm.label(crv, "CRV");
        vm.label(minter, "Minter");
        vm.label(gauge, "Gauge");
        vm.label(address(this), "test");

        vm.prank(alice);
        asset.approve(address(vault), type(uint).max);

        vm.prank(bob);
        asset.approve(address(vault), type(uint).max);
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function increasePricePerShare(uint256 amount) public {
        deal(
            address(asset),
            address(vault),
            amount
        );
    }

    function test__deposit(uint amount) public {
        amount = bound(amount, 1e10, 1e22);
        deal(address(asset), alice, amount);
        vm.prank(alice);
        vault.deposit(amount, alice);
    }
}