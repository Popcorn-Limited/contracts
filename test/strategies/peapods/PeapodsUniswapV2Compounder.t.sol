// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {PeapodsDepositorUniswapV2Compounder, SwapStep} from "../../../src/strategies/peapods/PeapodsUniswapV2Compounder.sol";
import {IStakedToken} from "../../../src/strategies/peapods/PeapodsStrategy.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, Math} from "../BaseStrategyTest.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract PeapodsUniswapV2CompounderTest is BaseStrategyTest {
    using stdJson for string;
    using Math for uint256;

    address asset;
    address stakingContract;
    address[2] depositAssets;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/peapods/PeapodsUniV2Compounder.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        // Read strategy init values
        stakingContract = json_.readAddress(string.concat(".configs[", index_, "].specific.init.stakingContract")); 

        // Deploy Strategy
        PeapodsDepositorUniswapV2Compounder strategy = new PeapodsDepositorUniswapV2Compounder();

        strategy.initialize(
            testConfig_.asset, 
            address(this), 
            true, 
            abi.encode(stakingContract)
        );

        // Set Harvest values
        address router = json_.readAddress(string.concat(".configs[", index_, "].specific.harvest.uniswapRouter"));
        
        // assets to buy with rewards and to add to liquidity 
        depositAssets[0] = json_.readAddress(
            string.concat(".configs[", index_, "].specific.harvest.depositAssets[0]")
        );
        depositAssets[1] = json_.readAddress(
            string.concat(".configs[", index_, "].specific.harvest.depositAssets[1]")
        ); 

        // set Uniswap trade paths
        SwapStep[] memory swaps = new SwapStep[](2);
        
        uint256 lenSwap0 = json_.readUint(
            string.concat(".configs[", index_, "].specific.harvest.tradePaths[0].length")
        );
        address[] memory swap0 = new address[](lenSwap0); // PEAS - WETH - DAI - pDAI
        for(uint256 i=0; i<lenSwap0; i++) {
            swap0[i] = json_.readAddress(
                string.concat(".configs[", index_, "].specific.harvest.tradePaths[0].path[", vm.toString(i), "]"));
        }

        uint256 lenSwap1 = json_.readUint(string.concat(".configs[", index_, "].specific.harvest.tradePaths[1].length"));
        address[] memory swap1 = new address[](lenSwap1); // PEAS - WETH - DAI
        for(uint256 i=0; i<lenSwap1; i++) {
            swap1[i] = json_.readAddress(
                string.concat(".configs[", index_, "].specific.harvest.tradePaths[1].path[", vm.toString(i), "]"));
        }

        swaps[0] = SwapStep(swap0);
        swaps[1] = SwapStep(swap1);

        strategy.setHarvestValues(router, depositAssets, swaps);
        asset = strategy.asset();

        return IBaseStrategy(address(strategy));
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        string memory json = vm.readFile("./test/strategies/peapods/PeapodsUniV2Compounder.json");

        // Read strategy init values
        address staking = json.readAddress(string.concat(".configs[0].specific.init.stakingContract")); 

        // Deploy Strategy
        PeapodsDepositorUniswapV2Compounder strategy = new PeapodsDepositorUniswapV2Compounder();

        strategy.initialize(
            asset, 
            address(this), 
            true, 
            abi.encode(staking)
        );

        assertEq(strategy.owner(), address(this), "owner");

        verify_strategyInit();
    }

    function test_depositWithdraw() public {
        uint256 amount = 1 ether;
        deal(strategy.asset(), bob, amount);

        vm.startPrank(bob);
        IERC20(strategy.asset()).approve(address(strategy), type(uint256).max);
        strategy.deposit(amount, bob);

        uint256 totAssets = strategy.totalAssets();
        assertEq(totAssets, amount);

        strategy.redeem(IERC20(address(strategy)).balanceOf(address(bob)), bob, bob);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), 0);
        assertEq(IERC20(strategy.asset()).balanceOf(bob), totAssets);
    }

    function test__harvest() public override {
        uint256 amount = 100 ether;
        deal(strategy.asset(), bob, amount);

        vm.startPrank(bob);
        IERC20(strategy.asset()).approve(address(strategy), type(uint256).max);
        strategy.deposit(amount, bob);
        vm.stopPrank();

        // distribute rewards token to strategy as if they were claimed
        deal(address(0x02f92800F57BCD74066F5709F1Daa1A4302Df875), address(strategy), 10 ether);

        uint256 totAssetsBefore = strategy.totalAssets();

        strategy.harvest(abi.encode(0));
        
        // total assets have increased
        assertGt(strategy.totalAssets(), totAssetsBefore);
    }

    function test__withdrawDust() public {
        PeapodsDepositorUniswapV2Compounder strategyContract = PeapodsDepositorUniswapV2Compounder(address(strategy));

        // distribute deposit tokens in the strategy
        deal(depositAssets[0], address(strategy), 0.1 ether);
        assertEq(IERC20(depositAssets[0]).balanceOf(address(strategy)), 0.1 ether);

        strategyContract.withdrawDust(depositAssets[0]);
        assertEq(IERC20(depositAssets[0]).balanceOf(address(strategy)), 0);

        deal(depositAssets[1], address(strategy), 0.1 ether);
        assertEq(IERC20(depositAssets[1]).balanceOf(address(strategy)), 0.1 ether);

        strategyContract.withdrawDust(depositAssets[1]);
        assertEq(IERC20(depositAssets[1]).balanceOf(address(strategy)), 0);       
    }

    function testFail_withdrawDust_invalidToken() public {
        PeapodsDepositorUniswapV2Compounder strategyContract = PeapodsDepositorUniswapV2Compounder(address(strategy));
        deal(depositAssets[0], address(strategy), 0.1 ether);

        // only deposit tokens
        strategyContract.withdrawDust(address(strategy.asset()));

        // only owner
        strategyContract.withdrawDust(depositAssets[0]);
        vm.stopPrank();
    }

    function testFail_withdrawDust_onlyOwner() public {
        PeapodsDepositorUniswapV2Compounder strategyContract = PeapodsDepositorUniswapV2Compounder(address(strategy));
        deal(depositAssets[0], address(strategy), 0.1 ether);

        // only owner
        vm.startPrank(bob);
        strategyContract.withdrawDust(depositAssets[0]);
        vm.stopPrank();
    }

    function verify_strategyInit() public {
        assertEq(
            IERC20Metadata(address(strategy)).name(),
            string.concat("VaultCraft Peapods ", IERC20Metadata(address(asset)).name(), " Adapter"),
            "name"
        );
        assertEq(
            IERC20Metadata(address(strategy)).symbol(),
            string.concat("vcp-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(IERC20(asset).allowance(address(strategy), stakingContract), type(uint256).max, "allowance");
    }
}
