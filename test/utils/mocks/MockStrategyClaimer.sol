pragma solidity ^0.8.15;

import { IWithRewards } from "../../../src/interfaces/vault/IWithRewards.sol";
import { IERC20Upgradeable as IERC20 } from "openzeppelin-contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";

contract MockStrategyClaimer {
  event SelectorsVerified();
  event AdapterVerified();
  event StrategySetup();
  event StrategyExecuted();
  event Claimed(uint256 amount);

  function verifyAdapterSelectorCompatibility(bytes4[8] memory) public {
    emit SelectorsVerified();
  }

  function verifyAdapterCompatibility(bytes memory) public {
    emit AdapterVerified();
  }

  function setUp(bytes memory) public {
    emit StrategySetup();
  }

  function harvest() public {
    IWithRewards(address(this)).claim();
    address[] memory rewardTokens = IWithRewards(address(this)).rewardTokens();

    for (uint256 i; i < rewardTokens.length; i++) {
      emit Claimed(IERC20(rewardTokens[i]).balanceOf(address(this)));
    }

    emit StrategyExecuted();
  }
}
