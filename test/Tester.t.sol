// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {ERC4626Upgradeable, IERC20Upgradeable as IERC20, IERC20MetadataUpgradeable as IERC20Metadata, ERC20Upgradeable as ERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Vault, IERC4626} from "../src/vault/Vault.sol";
import {VaultFees} from "../src/interfaces/vault/IVault.sol";

struct MultiCall {
    address target;
    bytes[] data;
    uint256 dynIndex;
    bool doesReturn;
}

contract ExternalProtocol {
    function returnNumber(uint256) external returns (uint256) {
        return uint256(1);
    }

    function returnAddress(uint256) external returns (address) {
        return address(1);
    }

    function returnNothing(uint256) external {
        return;
    }
}

contract Tester is Test {
    ExternalProtocol externalProtocol;

    function setUp() public {
        externalProtocol = new ExternalProtocol();
    }

    function test_stuff() public {
        bytes[] memory d = new bytes[](2);
        d[0] = bytes("a");
        d[1] = bytes("b");
        emit log_bytes(bytes.concat(d[0], d[1]));
        emit log_bytes(_concatArray(d));

        (bool success1, bytes memory res1) = address(externalProtocol).call(
            abi.encodeWithSelector(
                bytes4(keccak256("returnNumber(uint256)")),
                uint256(0)
            )
        );
        uint256 decoded1 = abi.decode(res1, (uint256));
        emit log_named_uint("1", decoded1);

        (bool success2, bytes memory res2) = address(externalProtocol).call(
            abi.encodeWithSelector(
                bytes4(keccak256("returnAddress(uint256)")),
                uint256(0)
            )
        );
        uint256 decoded2 = abi.decode(res2, (uint256));
        emit log_named_uint("2", decoded2);

        emit log_bytes(abi.encode(bytes4(keccak256("returnNothing(uint256)"))));
        emit log_bytes(abi.encodePacked(uint256(1e18)));
        emit log_bytes(
            abi.encodeWithSelector(
                bytes4(keccak256("returnNothing(uint256)")),
                uint256(1e18)
            )
        );

        // (bool success3, bytes memory res3) = address(externalProtocol).call(
        // abi.encodeWithSelector(
        //     bytes4(keccak256("returnNothing(uint256)")),
        //     uint256(0)
        // )
        // );
        // uint256 decoded3 = abi.decode(res3, (uint256));
        // emit log_named_uint("3", decoded3);
    }

    // function test_stuff2() public {
    //     bytes[] memory data = new bytes[](2);
    //     data[0] =
    //     MultiCall memory callData = MultiCall()
    // }

    function _execute(
        MultiCall memory callData,
        uint256 value
    ) internal returns (uint256) {
        if (callData.dynIndex > 0)
            callData.data[callData.dynIndex] = abi.encode(value);
        (bool success, bytes memory res) = callData.target.call(
            _concatArray(callData.data)
        );
        if (callData.doesReturn) return abi.decode(res, (uint256));
        return 0;
    }

    function _concatArray(
        bytes[] memory array
    ) internal returns (bytes memory) {
        if (array.length == 1) return array[0];
        bytes memory result = array[0];
        for (uint256 i = 1; i < array.length; ++i) {
            result = bytes.concat(result, array[i]);
        }
        return result;
    }
}
