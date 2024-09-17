// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

interface IAsyncVault {
  struct RedeemRequest {
        uint256 shares;
        uint256 requestTime;
    }

  function redeemRequests(address recipient, address multisig) external view returns (RedeemRequest)
}

contract WithdrawalModule {
  address controller;
    address vault;
    uint256 withdrawalPeriod;

    constructor() {}

    function checkViolation(bytes memory data) external view returns(bool){
      return _checkViolation(data);
    }

    function _checkViolation(bytes memory data) internal view returns(bool){
      (address recipient, address multisig) = abi.decode(data,(address,address));

      IAsyncVault.RedeemRequest memory redeemRequest = IAsyncVault(vault).redeemRequests(recipient,multisig);

      if(redeemRequest.requestTime + withdrawalPeriod < block.timestamp && redeemRequest.shares > 0){
        return true;
      }
      return false;
    }

    function takeoverSafe(bytes memory data) external {
      require(_checkViolation(data) ,"not valid");


    }
}
