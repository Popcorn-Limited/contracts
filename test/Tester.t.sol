pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {ERC4626Upgradeable, IERC20, IERC20Metadata, ERC20Upgradeable as ERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {PendleLpOracle} from "src/peripheral/oracles/adapter/PendleLpOracle.sol";
import {CrossOracle, OracleStep} from "src/peripheral/oracles/adapter/CrossOracle.sol";

contract Tester is Test {

    function setUp() public {
        vm.selectFork(vm.createFork("mainnet"));
    }

    function testA() public {}

    function testB() public {}
}
