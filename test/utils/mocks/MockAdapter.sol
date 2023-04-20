// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import { AdapterBase, IERC20 } from "../../../src/vault/adapter/abstracts/AdapterBase.sol";

contract MockYieldFarm {
  IERC20 asset;

  constructor(IERC20 asset_) {
    asset = asset_;
  }

  function withdraw(uint256 amount) external {
    asset.transfer(msg.sender, amount);
  }
}

contract MockAdapter is AdapterBase {
  uint256 public beforeWithdrawHookCalledCounter = 0;
  uint256 public afterDepositHookCalledCounter = 0;
  uint256 public initValue;

  MockYieldFarm internal mockYieldFarm;

  /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

  function initialize(
    bytes memory adapterInitData,
    address,
    bytes memory mockInitData
  ) external initializer {
    __AdapterBase_init(adapterInitData);

    mockYieldFarm = new MockYieldFarm(IERC20(asset()));

    if (mockInitData.length > 0) initValue = abi.decode(mockInitData, (uint256));
  }

  /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

  function _totalAssets() internal view override returns (uint256) {
    return IERC20(asset()).balanceOf(address(mockYieldFarm));
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

  function _protocolDeposit(uint256 assets, uint256) internal override {
    afterDepositHookCalledCounter++;
    IERC20(asset()).transfer(address(mockYieldFarm), assets);
  }

  function _protocolWithdraw(uint256 assets, uint256) internal override {
    beforeWithdrawHookCalledCounter++;
    mockYieldFarm.withdraw(assets);
  }
}
