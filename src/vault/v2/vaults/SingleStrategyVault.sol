// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {BaseVault, IERC20, BaseVaultConfig} from "../base/BaseVault.sol";
import {IBaseAdapter} from "../base/interfaces/IBaseAdapter.sol";

contract SingleStrategyVault is BaseVault {
    IBaseAdapter public strategy;

    function initialize(
        BaseVaultConfig memory _vaultConfig,
        address _strategy
    ) external initializer {
        __BaseVault__init(_vaultConfig);

        if (_strategy == address(0)) revert InvalidStrategy(_strategy);

        bool useLpToken = IBaseAdapter(_strategy).useLpToken();
        address strategyAsset = useLpToken
            ? IBaseAdapter(_strategy).lpToken()
            : IBaseAdapter(_strategy).underlying();
        if (_vaultConfig.asset != strategyAsset)
            revert InvalidStrategy(_strategy);

        strategy = IBaseAdapter(_strategy);

        _vaultConfig.asset.safeApprove(_strategy, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function _totalAssets() internal view override returns (uint256) {
        return strategy.totalAssets();
    }

    function _maxDeposit(address) internal view override returns (uint256) {
        return strategy.maxDeposit();
    }

    function _maxMint(address) internal view override returns (uint256) {
        return strategy.maxDeposit();
    }

    function _maxWithdraw(address) internal view override returns (uint256) {
        return strategy.maxWithdraw();
    }

    function _maxRedeem(address) internal view override returns (uint256) {
        return strategy.maxWithdraw();
    }

    /*//////////////////////////////////////////////////////////////
                      DEPOSIT / WITHDRAW LOGIC
    //////////////////////////////////////////////////////////////*/

    function _strategyDeposit(uint256 assets, uint256) internal override {
        strategy.deposit(assets);
    }

    function _strategyWithdraw(
        uint256 assets,
        uint256,
        address receiver
    ) internal override {
        strategy.withdraw(assets, receiver);
    }
}
