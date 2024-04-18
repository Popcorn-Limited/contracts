// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {IBaseStrategy} from "../src/interfaces/IBaseStrategy.sol";
import {BalancerCompounder, HarvestValue, BatchSwapStep, IAsset} from "../src/strategies/balancer/BalancerCompounder.sol";

contract DeployStrategy is Script {
    address deployer;

    // Base strategy config
    address asset;
    address owner;
    bool autoHarvest;

    // Protool specific config
    address gauge;
    address balVault;
    address balMinter;

    // Harvest values
    BatchSwapStep[] swaps;
    IAsset[] assets;
    int256[] limits;
    uint256 minTradeAmount;
    address baseAsset;
    address[] underlyings;
    uint256 indexIn;
    uint256 amountsInLen;
    bytes32 balPoolId;

    function run() public {
        /// ---------- Strategy Configuration ---------- ///

        // @dev Edit the base strategy config
        asset = address(0);
        owner = address(0);
        autoHarvest = false;

        // @dev Edit the protocol specific config
        gauge = 0xee01c0d9c0439c94D314a6ecAE0490989750746C;
        balVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        balMinter = 0x239e55F427D44C3cc793f49bFB507ebe76638a2b;

        // @dev Edit the harvest values

        // Add BAL swap
        swaps.push(
            BatchSwapStep(
                0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014,
                0,
                1,
                0,
                ""
            )
        ); // trade BAL for WETH
        assets.push(IAsset(0xba100000625a3754423978a60c9317c58a424e3D)); // BAL
        assets.push(IAsset(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)); // WETH
        limits.push(type(int256).max); // BAL limit
        limits.push(-1); // WETH limit

        // Set minTradeAmounts
        minTradeAmount = 10e18;

        // Set underlyings
        underlyings.push(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH
        underlyings.push(0xE7e2c68d3b13d905BBb636709cF4DfD21076b9D2); // LP-Token
        underlyings.push(0xf951E335afb289353dc249e82926178EaC7DEd78); // swETH

        // Set other values
        baseAsset = address(0);
        indexIn = uint256(0);
        amountsInLen = uint256(0);
        balPoolId = bytes32("");

        /// ---------- Actual Deployment ---------- ///

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        AuraCompounder strategy = new AuraCompounder();

        strategy.initialize(
            asset,
            owner,
            autoHarvest,
            abi.encode(gauge, balVault, balMinter)
        );

        strategy.setHarvestValues(
            HarvestValue(
                swaps,
                assets,
                limits,
                minTradeAmount,
                baseAsset,
                underlyings,
                indexIn,
                amountsInLen,
                balPoolId
            )
        );

        vm.stopBroadcast();
    }
}
