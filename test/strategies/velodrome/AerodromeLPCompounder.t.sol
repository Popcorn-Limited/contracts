// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {VelodromeLPCompounder, SwapStep, Route} from "src/strategies/velodrome/VelodromeLPCompounder.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, Math} from "../BaseStrategyTest.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract VelodromeLPCompounderTest is BaseStrategyTest {
    using stdJson for string;
    using Math for uint256;

    address asset;
    address gauge;
    address[2] depositAssets;
    address[] rewardTokens;
    
    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/velodrome/AerodromeLPCompounderConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        // Read strategy init values
        gauge = json_.readAddress(string.concat(".configs[", index_, "].specific.init.gauge"));

        // Deploy Strategy
        VelodromeLPCompounder strategy = new VelodromeLPCompounder();
        
        strategy.initialize(testConfig_.asset, address(this), true, abi.encode(gauge));

        // Set Harvest values
        address router = json_.readAddress(string.concat(".configs[", index_, "].specific.harvest.velodromeRouter"));

        // set Velo trade paths
        SwapStep[] memory swaps = new SwapStep[](2);

        {
            address from;
            address to;
            bool stable;
            address factory;

            uint256 lenSwap0 = json_.readUint(string.concat(".configs[", index_, "].specific.harvest.tradePaths[0].length"));
            for (uint256 i = 0; i < lenSwap0; i++) {
                from = json_.readAddress(
                    string.concat(".configs[", index_, "].specific.harvest.tradePaths[0].routes[", vm.toString(i), "].from")
                );

                to = json_.readAddress(
                    string.concat(".configs[", index_, "].specific.harvest.tradePaths[0].routes[", vm.toString(i), "].to")
                );

                stable = json_.readBool(
                    string.concat(".configs[", index_, "].specific.harvest.tradePaths[0].routes[", vm.toString(i), "].stable")
                );

                factory = json_.readAddress(
                    string.concat(".configs[", index_, "].specific.harvest.tradePaths[0].routes[", vm.toString(i), "].factory")
                );

                depositAssets[0] = to;
                swaps[0].tradeSwap = abi.encode(from, to, stable, factory);
            }

            uint256 lenSwap1 = json_.readUint(string.concat(".configs[", index_, "].specific.harvest.tradePaths[1].length"));
            for (uint256 i = 0; i < lenSwap1; i++) {
                from = json_.readAddress(
                    string.concat(".configs[", index_, "].specific.harvest.tradePaths[1].routes[", vm.toString(i), "].from")
                );

                to = json_.readAddress(
                    string.concat(".configs[", index_, "].specific.harvest.tradePaths[1].routes[", vm.toString(i), "].to")
                );

                stable = json_.readBool(
                    string.concat(".configs[", index_, "].specific.harvest.tradePaths[1].routes[", vm.toString(i), "].stable")
                );

                factory = json_.readAddress(
                    string.concat(".configs[", index_, "].specific.harvest.tradePaths[1].routes[", vm.toString(i), "].factory")
                );

                depositAssets[1] = to;
                swaps[1].tradeSwap = abi.encode(from, to, stable, factory);
            }
        }

        // rewards
        uint256 rewLen = json_.readUint(string.concat(".configs[", index_, "].specific.harvest.rewards.length"));
        // address[] memory rewardTokens = new address[](rewLen);
        for (uint256 i = 0; i < rewLen; i++) {
            rewardTokens.push(
                json_.readAddress(
                    string.concat(".configs[", index_, "].specific.harvest.rewards.tokens[", vm.toString(i), "]")
                )
            );
        }

        strategy.setHarvestValues(router, rewardTokens, swaps);

        asset = strategy.asset();

        return IBaseStrategy(address(strategy));
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        string memory json = vm.readFile(path);

        // Read strategy init values
        gauge = json.readAddress(string.concat(".configs[0].specific.init.gauge"));

        // Deploy Strategy
        VelodromeLPCompounder strategy = new VelodromeLPCompounder();

        strategy.initialize(asset, address(this), true, abi.encode(gauge));

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

        uint256 totAssetsBefore = strategy.totalAssets();

        // distribute rewards token to strategy as if they were claimed
        deal(address(rewardTokens[0]), address(strategy), 10 ether);

        strategy.harvest(abi.encode(0));

        // total assets have increased
        assertGt(strategy.totalAssets(), totAssetsBefore);
    }

    function test__withdrawDust() public {
        VelodromeLPCompounder strategyContract = VelodromeLPCompounder(address(strategy));

        // distribute deposit tokens in the strategy
        vm.prank(0xD34EA7278e6BD48DefE656bbE263aEf11101469c);
        IERC20(depositAssets[0]).transfer(address(strategy), 1 gwei);
        assertEq(IERC20(depositAssets[0]).balanceOf(address(strategy)), 1 gwei);

        strategyContract.withdrawDust(depositAssets[0]);
        assertEq(IERC20(depositAssets[0]).balanceOf(address(strategy)), 0);

        vm.prank(0x2ae9DF02539887d4EbcE0230168a302d34784c82);
        IERC20(depositAssets[1]).transfer(address(strategy), 1 gwei);
        assertEq(IERC20(depositAssets[1]).balanceOf(address(strategy)), 1 gwei);

        strategyContract.withdrawDust(depositAssets[1]);
        assertEq(IERC20(depositAssets[1]).balanceOf(address(strategy)), 0);
    }

    function testFail_withdrawDust_invalidToken() public {
        VelodromeLPCompounder strategyContract = VelodromeLPCompounder(address(strategy));
        deal(depositAssets[1], address(strategy), 0.1 ether);

        // only deposit tokens
        strategyContract.withdrawDust(address(strategy.asset()));
    }

    function testFail_withdrawDust_onlyOwner() public {
        VelodromeLPCompounder strategyContract = VelodromeLPCompounder(address(strategy));
        deal(depositAssets[1], address(strategy), 0.1 ether);

        // only owner
        vm.startPrank(bob);
        strategyContract.withdrawDust(depositAssets[1]);
        vm.stopPrank();
    }

    function verify_strategyInit() public {
        assertEq(
            IERC20Metadata(address(strategy)).name(),
            string.concat("VaultCraft Velodrome Compounder ", IERC20Metadata(address(asset)).name(), " Adapter"),
            "name"
        );
        assertEq(
            IERC20Metadata(address(strategy)).symbol(),
            string.concat("vc-velo-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(IERC20(asset).allowance(address(strategy), gauge), type(uint256).max, "allowance");
    }
}
