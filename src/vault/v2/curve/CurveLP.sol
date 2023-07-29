pragma solidity ^0.8.15;

import {BaseVaultInitData, BaseVault} from "../BaseVault.sol";
import {IGauge, IMinter} from "../../adapter/curve/ICurve.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/interfaces/IERC20Metadata.sol";

abstract contract CurveLP is BaseVault {
    address crv;
    IGauge gauge;
    IMinter minter;

    function __CurveLP__init(BaseVaultInitData calldata initData, address _gauge, address _minter, address _asset) internal onlyInitializing {
        __BaseVault__init(initData);
        gauge = IGauge(_gauge);
        minter = IMinter(_minter);
        crv = IMinter(_minter).token();

        IERC20(_asset).approve(_gauge, type(uint).max);

        updateRewardTokens();
    }


    function _claim() internal override {
        minter.mint(address(gauge));
    }
    
    /// @dev used to retrieve the current reward tokens in case they've changed.
    /// callable by anyone
    function updateRewardTokens() public override {
        delete rewardTokens;

        // we don't know the exact number of reward tokens. So we brute force it
        // We could use `reward_count()` to get the exact number.  But, that function is only
        // available from LiquidityGaugeV4 onwards.
        
        // Curve only allows 8 reward tokens per gauge
        address[] memory _rewardTokens = new address[](8);
        uint rewardCount = 0;
        for (uint i; i < 8;) {
            try gauge.reward_tokens(i) returns (address token) {
                if (token == address(0)) {
                    // no more reward tokens left
                    break;
                }

                unchecked {++rewardCount;}
                _rewardTokens[i] = token;
            } catch {
                // LiquidityGaugeV1 doesn't implement `reward_tokens()` so we have to add a try/catch block
                // 3pool Gauge: https://etherscan.io/address/0xbfcf63294ad7105dea65aa58f8ae5be2d9d0952a#code
                break;
            }
            unchecked {++i;}
        }
        // CRV token is always a reward token that's not explicitly specified in the gauge contract.
        rewardTokens.push(crv);

        for (uint i; i < rewardCount;) {
            rewardTokens.push(_rewardTokens[i]);
            unchecked {++i;}
        }
    }
    
    function _protocolDeposit(uint amount, uint) internal override {
        gauge.deposit(amount);
    }

    function _protocolWithdraw(uint amount, uint) internal override {
        gauge.withdraw(amount);
    }

    function _totalAssets() internal view override returns (uint) {
        return gauge.balanceOf(address(this));
    }
}
