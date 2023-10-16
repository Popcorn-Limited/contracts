pragma solidity ^0.8.15;
import {
  BaseAdapter,
  AdapterConfig,
  ProtocolConfig,
  IERC20Metadata
} from "../../../src/base/BaseAdapter.sol";
import {
  ERC4626Upgradeable
} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract MockStrategyV2 is BaseAdapter, ERC20Upgradeable {

  function __MockAdapter_init(
    AdapterConfig memory _adapterConfig,
    ProtocolConfig memory _protocolConfig
  ) public initializer {
    __BaseAdapter_init(_adapterConfig);
  }

  function _totalUnderlying() internal view override returns (uint256) {
    return totalSupply();
  }

  function _deposit(uint256 amount,  address caller) internal override {
    underlying.transferFrom(msg.sender, address(this), amount);
    _mint(msg.sender, amount);
  }

  function _withdraw(uint256 amount, address receiver) internal override {
    _burn(msg.sender, amount);
    underlying.transfer(receiver, amount);
  }
}
