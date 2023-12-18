pragma solidity ^0.8.15;
import {
  BaseAdapter,
  AdapterConfig,
  IERC20Metadata
} from "../../../src/base/BaseAdapter.sol";
import {
  ERC4626Upgradeable
} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract MockStrategyV2 is BaseAdapter, ERC20Upgradeable {

  function __MockAdapter_init(
    AdapterConfig memory _adapterConfig
  ) public initializer {
    __BaseAdapter_init(_adapterConfig);
  }

  function _totalUnderlying() internal view override returns (uint256) {
    return underlying.balanceOf(address(this));
  }

  function _totalLP() internal view override returns (uint) {
    return lpToken.balanceOf(address(this));
  }

  function _deposit(uint256 amount,  address caller) internal override {
    if (useLpToken) {
      lpToken.transferFrom(caller, address(this), amount);
    } else {
      underlying.transferFrom(caller, address(this), amount);
    }
    _mint(msg.sender, amount);
  }

  // these are never executed by the strategy so we leave them empty
  function _depositUnderlying(uint) internal pure override {}
  function _depositLP(uint) internal pure override {}
  function _withdrawUnderlying(uint) internal pure override {}
  function _withdrawLP(uint) internal pure override {}

  function _withdraw(uint256 amount, address receiver) internal override {
    _burn(msg.sender, amount);
    if (useLpToken) {
      lpToken.transfer(receiver, amount);
    } else {
      underlying.transfer(receiver, amount);
    }
  }

  function _claim() internal pure override {}
}
