pragma solidity ^0.8.15;
import {
  BaseAdapter,
  AdapterConfig,
  ProtocolConfig,
  IERC20Metadata
} from "../../../src/base/BaseAdapter.sol";
import { MockStrategy } from "./MockStrategy.sol";
import {
  ERC4626Upgradeable
} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { BaseStrategyRewardClaimer } from "../../../src/base/BaseStrategyRewardClaimer.sol";
import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20Upgradeable as IERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20 as IERC20_ } from "openzeppelin-contracts/token/ERC20/IERC20.sol";


contract MockRewardClaimerStrategy is MockStrategy, BaseStrategyRewardClaimer {

  function __MockRewardClaimerStrategy_init(
    AdapterConfig memory _adapterConfig,
    ProtocolConfig memory _protocolConfig
  ) public {
    __MockAdapter_init(_adapterConfig, _protocolConfig);
  }

  function deposit(uint256 amount) external override onlyVault whenNotPaused {
    _accrueVaultReward(msg.sender);
    _deposit(amount, msg.sender);
  }

  function withdraw(uint256 amount, address receiver) external override onlyVault {
    _accrueVaultReward(msg.sender);
    _withdraw(amount, receiver);
  }

  function updateRewardIndex(IERC20_ rewardToken, uint256 reward) external {
    _accrueStrategyReward(rewardToken, reward);
  }

  function withdrawVaultReward() external onlyVault {
    _withdrawAccruedVaultReward();
  }

  function _getRewardTokens() public view override returns (IERC20[] memory) {
    return getRewardTokens();
  }

  function _totalDeposits() internal view override returns(uint256) {
    return _totalAssets();
  }

  function _balanceOf(address vault) internal view override returns(uint256) {
    return balanceOf(vault);
  }

  function _decimals() internal view override returns(uint256) {
    return decimals();
  }
}
