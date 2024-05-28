// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {
    ERC4626Upgradeable,
    IERC20,
    IERC20Metadata,
    ERC20Upgradeable as ERC20
} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

interface VaultRouter_I {
    function depositAndStake(address vault, address gauge, uint256 assetAmount, address receiver) external;

    function unstakeAndWithdraw(address vault, address gauge, uint256 burnAmount, address receiver) external;
}

struct BatchSwapStep {
    bytes32 poolId;
    uint256 assetInIndex;
    uint256 assetOutIndex;
    uint256 amount;
    bytes userData;
}

struct FixedAddressArray {
    address[11] fixed_;
}

struct FixedUintArray {
    uint256[5] swapParams;
}

interface IAsset {}

contract Tester is Test {
    using stdJson for string;

    VaultRouter_I router = VaultRouter_I(0x4995F3bb85E1381D02699e2164bC1C6c6Fa243cd);
    address Vault = address(0x7CEbA0cAeC8CbE74DB35b26D7705BA68Cb38D725);
    address adapter = address(0xF6Fe643cb8DCc3E379Cdc6DB88818B09fdF2200d);
    IERC20 asset = IERC20(0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7);

    function setUp() public {
        vm.selectFork(vm.createFork("mainnet"));
    }

    function testA() public {
        emit log_uint(bytes("").length);
        emit log_address(abi.decode(abi.encode(""), (address)));
    }
}
