// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockGauge is ERC20 {
    address public lpToken;

    constructor(address _lpToken) ERC20("Mock Curve Gauge", "MCG") {
        lpToken = _lpToken;
    }

    function deposit(uint256 _value) external {
        deposit(_value, msg.sender);
    }

    function deposit(uint256 _value, address _addr) public {
        ERC20(lpToken).transferFrom(msg.sender, address(this), _value);
        _mint(_addr, _value);
    }

    function withdraw(uint256 _value) external {
        withdraw(_value, msg.sender);
    }

    function withdraw(uint256 _value, address _addr) public {
        _burn(msg.sender, _value);
        ERC20(lpToken).transfer(_addr, _value);
    }
}
