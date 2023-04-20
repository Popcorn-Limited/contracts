pragma solidity ^0.8.15;

contract MockStrategy {
  event SelectorsVerified();
  event AdapterVerified();
  event StrategySetup();
  event StrategyExecuted();

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
    emit StrategyExecuted();
  }
}
