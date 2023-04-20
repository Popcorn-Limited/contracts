pragma solidity ^0.8.15;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

contract ClonableWithoutInitData is Initializable {
    uint256 public immutable val = uint256(10);

    bool public initDone;

    function initialize() external initializer {
        initDone = true;
    }

    function fail() external pure {
        revert("This always reverts");
    }
}
