pragma solidity ^0.8.15;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

contract ClonableWithInitData is Initializable {
    uint256 public val;

    function initialize(uint256 _val) external initializer {
        val = _val;
    }
}
