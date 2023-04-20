// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import { ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IUniswapRouterV2 } from "../../interfaces/external/uni/IUniswapRouterV2.sol";
import { IAdapter } from "../../interfaces/vault/IAdapter.sol";
import { IWithRewards } from "../../interfaces/vault/IWithRewards.sol";
import { StrategyBase } from "./StrategyBase.sol";

contract Pool2SingleAssetCompounder is StrategyBase {
  error NoValidTradePath();

  function verifyAdapterCompatibility(bytes memory data) public override {
    address router = abi.decode(data, (address));
    address asset = IAdapter(address(this)).asset();

    // Verify Trade Path exists
    address[] memory tradePath = new address[](2);
    tradePath[1] = asset;

    address[] memory rewardTokens = IWithRewards(address(this)).rewardTokens();
    uint256 len = rewardTokens.length;
    for (uint256 i = 0; i < len; i++) {
      tradePath[0] = rewardTokens[i];

      uint256[] memory amountsOut = IUniswapRouterV2(router).getAmountsOut(ERC20(asset).decimals() ** 10, tradePath);
      if (amountsOut[amountsOut.length] == 0) revert NoValidTradePath();
    }
  }

  function setUp(bytes memory data) public override {
    address router = abi.decode(data, (address));

    // Approve all rewardsToken for trading
    address[] memory rewardTokens = IWithRewards(address(this)).rewardTokens();
    uint256 len = rewardTokens.length;
    for (uint256 i = 0; i < len; i++) {
      ERC20(rewardTokens[i]).approve(router, type(uint256).max);
    }
  }

  /// @notice claim all token rewards and trade them for the underlying asset
  function harvest() public override {
    address router = abi.decode(IAdapter(address(this)).strategyConfig(), (address));
    address asset = IAdapter(address(this)).asset();
    address[] memory rewardTokens = IWithRewards(address(this)).rewardTokens();

    IWithRewards(address(this)).claim(); // hook to accrue/pull in rewards, if needed

    address[] memory tradePath = new address[](2);
    tradePath[1] = asset;

    uint256 len = rewardTokens.length;
    // send all tokens to destination
    for (uint256 i = 0; i < len; i++) {
      uint256 amount = ERC20(rewardTokens[i]).balanceOf(address(this));

      if (amount > 0) {
        tradePath[0] = rewardTokens[i];

        IUniswapRouterV2(router).swapExactTokensForTokens(amount, 0, tradePath, address(this), block.timestamp);
      }
    }
    IAdapter(address(this)).strategyDeposit(ERC20(asset).balanceOf(address(this)), 0);
  }
}
