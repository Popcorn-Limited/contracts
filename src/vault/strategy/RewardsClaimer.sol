// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import { SafeERC20Upgradeable as SafeERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC20Upgradeable as ERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IAdapter } from "../../interfaces/vault/IAdapter.sol";
import { IWithRewards } from "../../interfaces/vault/IWithRewards.sol";
import { StrategyBase } from "./StrategyBase.sol";

contract RewardsClaimer is StrategyBase {
  using SafeERC20 for ERC20;

  event ClaimRewards(address indexed rewardToken, uint256 amount);

  /// @notice claim all token rewards
  function harvest() public override {
    address rewardDestination = abi.decode(IAdapter(address(this)).strategyConfig(), (address));

    IWithRewards(address(this)).claim(); // hook to accrue/pull in rewards, if needed

    address[] memory rewardTokens = IWithRewards(address(this)).rewardTokens();
    uint256 len = rewardTokens.length;
    // send all tokens to destination
    for (uint256 i = 0; i < len; i++) {
      ERC20 token = ERC20(rewardTokens[i]);
      uint256 amount = token.balanceOf(address(this));

      token.safeTransfer(rewardDestination, amount);

      emit ClaimRewards(address(token), amount);
    }
  }
}
