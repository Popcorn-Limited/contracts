// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {AnyDepositorV2, IERC20} from "src/strategies/any/v2/AnyDepositorV2.sol";
import {PendingTarget, CallStruct} from "src/strategies/any/v2/AnyConverterV2.sol";

contract Deploy is Script {
    using stdJson for string;

    function run() public returns (AnyDepositorV2 strategy) {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/script/deploy/any/v2/AnyDepositorV2DeployConfig.json"
            )
        );

        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        strategy = new AnyDepositorV2();

        // Construct `pendingTargets`
        address[] memory targets = json.readAddressArray(
            ".strategyInit.targets.address"
        );
        bytes32[] memory sigsLong = json.readBytes32Array(
            ".strategyInit.targets.selector"
        );

        if (targets.length != sigsLong.length) {
            revert("targets and sigsLong must have the same length");
        }

        PendingTarget[] memory pendingTargets = new PendingTarget[](
            targets.length
        );
        for (uint256 i = 0; i < targets.length; i++) {
            pendingTargets[i] = PendingTarget({
                target: targets[i],
                selector: bytes4(sigsLong[i]),
                allowed: true
            });
        }

        // Construct `pendingAllowances`
        targets = json.readAddressArray(
            ".strategyInit.pendingAllowances.address"
        );
        bytes[] memory data = json.readBytesArray(
            ".strategyInit.pendingAllowances.data"
        );

        if (targets.length != data.length) {
            revert("targets and data must have the same length");
        }

        CallStruct[] memory pendingAllowances = new CallStruct[](
            targets.length
        );
        for (uint256 i = 0; i < pendingAllowances.length; i++) {
            pendingAllowances[i] = CallStruct({
                target: targets[i],
                data: data[i]
            });
        }

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoDeposit"),
            abi.encode(
                json.readAddress(".strategyInit.yieldAsset"),
                json.readAddress(".strategyInit.oracle"),
                json.readUint(".strategyInit.slippage"),
                pendingTargets,
                pendingAllowances
            )
        );

        vm.stopBroadcast();
    }
}
