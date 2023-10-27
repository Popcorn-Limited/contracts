// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {IBaseAdapter} from "../base/interfaces/IBaseAdapter.sol";
import {BaseVaultRewardClaimer} from "../base/BaseVaultRewardClaimer.sol";
import {BaseVault, IERC20, BaseVaultConfig, VaultFees} from "../base/BaseVault.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract RewardClaimerVault is BaseVault, BaseVaultRewardClaimer {
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
        if (address(_vaultConfig.asset_) != strategyAsset)
            revert InvalidStrategy(_strategy);

        strategy = IBaseAdapter(_strategy);

        _vaultConfig.asset_.approve(_strategy, type(uint256).max);
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
                        REWARD CLAIMER LOGIC
    //////////////////////////////////////////////////////////////*/
    function withdrawReward() external {
        strategy.withdrawVaultReward();
        _withdrawAccruedUserReward();
    }

    /*//////////////////////////////////////////////////////////////
                      DEPOSIT / WITHDRAW LOGIC
    //////////////////////////////////////////////////////////////*/
    function deposit(
        uint assets,
        address receiver
    ) public override returns (uint shares) {
        _accrueUserReward(receiver);
        return super.deposit(assets, receiver);
    }

    function mint(
        uint shares,
        address receiver
    ) public override returns (uint assets) {
        _accrueUserReward(msg.sender);
        return super.mint(shares, receiver);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256) {
        _accrueUserReward(owner);
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256) {
        _accrueUserReward(owner);
        return super.redeem(shares, receiver, owner);
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL DEPOSIT / WITHDRAW LOGIC
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

    /*//////////////////////////////////////////////////////////////
                  INTERNAL REWARD CLAIMER LOGIC
    //////////////////////////////////////////////////////////////*/
    address[] public strategies;
    function _getStrategies() internal override returns(address[] memory) {
        strategies.push(address(strategy));
        return strategies;
    }

    function _stakedAssetDecimals() internal override returns(uint256) {
        return _decimals;
    }
}
