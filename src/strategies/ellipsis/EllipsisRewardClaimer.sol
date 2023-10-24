// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {
    IERC20,
    AdapterConfig,
    ProtocolConfig,
    EllipsisLpStakingAdapter
} from "../../adapter/ellipsis/lpStaking/EllipsisLpStakingAdapter.sol";
import { BaseStrategyRewardClaimer } from "../../base/BaseStrategyRewardClaimer.sol";


contract EllipsisRewardClaimer is EllipsisLpStakingAdapter, BaseStrategyRewardClaimer {

    function initialize(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) external initializer {
        __EllipsisLpStakingAdapter_init(_adapterConfig, _protocolConfig);
    }

    function deposit(uint256 amount) external override onlyVault whenNotPaused {
        _deposit(amount, msg.sender);
    }

    function withdraw(uint256 amount, address receiver) external override onlyVault {
        _withdraw(amount, receiver);
    }

    function getReward() onlyVault external {
        _withdrawAccruedReward();
    }

    function _getRewardTokens() public view override returns (IERC20[] memory) {
        return getRewardTokens();
    }

    function _totalDeposits() internal view override returns(uint256) {
        return _totalAssets();
    }

    function _balanceOf(address vault) internal view override returns(uint256) {
        return 0; // todo: refactor
    }

    function _decimals() internal view override returns(uint256) {
        return 0; // todo: refactor
    }
}
