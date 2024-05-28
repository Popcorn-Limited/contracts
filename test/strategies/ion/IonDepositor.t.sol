// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {IonDepositor, SafeERC20, IERC20} from "../../../src/strategies/ion/IonDepositor.sol";
import {IIonPool, IWhitelist} from "../../../src/strategies/ion/IIonProtocol.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";

contract IonDepositorTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/ion/IonDepositorTestConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        // Get Ion Addresses
        IIonPool ionPool = IIonPool(json_.readAddress(string.concat(".configs[", index_, "].specific.ionPool")));
        IWhitelist whitelist = IWhitelist(json_.readAddress(string.concat(".configs[", index_, "].specific.whitelist")));
        address ionOwner = json_.readAddress(string.concat(".configs[", index_, "].specific.ionOwner"));

        vm.label(address(ionPool), "IonPool");

        // Remove Ions whitelist proof requirement
        vm.startPrank(ionOwner);
        whitelist.updateLendersRoot(0);
        ionPool.updateSupplyCap(100000e18);
        vm.stopPrank();

        // Deploy strategy
        IonDepositor strategy = new IonDepositor();

        strategy.initialize(testConfig_.asset, address(this), true, abi.encode(address(ionPool)));

        return IBaseStrategy(address(strategy));
    }

    function _increasePricePerShare(uint256 amount) internal override {
        address ionPool = address(IonDepositor(address(strategy)).ionPool());

        deal(testConfig.asset, ionPool, IERC20(testConfig.asset).balanceOf(ionPool) + amount);
    }
}
