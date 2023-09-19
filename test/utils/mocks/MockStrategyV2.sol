pragma solidity ^0.8.15;
import {
  IERC20,
  BaseAdapter,
  AdapterConfig,
  ProtocolConfig
} from "../../../src/vault/v2/base/BaseAdapter.sol";

contract MockStrategyV2 is BaseAdapter {

  function __MockAdapter_init(
    AdapterConfig memory _adapterConfig,
    ProtocolConfig memory _protocolConfig
  ) public initializer {
    __BaseAdapter_init(_adapterConfig);
  }

  function _totalLP() internal view override returns (uint256) {
    return 0;
  }

  function _deposit(uint256 amount) internal override {}

  function _depositLP(uint256 amount) internal override {}

  function _withdraw(uint256 amount, address receiver) internal override {}

  function _withdrawLP(uint256 amount) internal override {}

  function _claim() internal override {}
}
