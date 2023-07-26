pragma solidity ^0.8.15;

import {BaseVaultInitData, BaseVault} from "../BaseVault.sol";
import {IGauge, IMinter} from "../../adapter/curve/ICurve.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/interfaces/IERC20Metadata.sol";

abstract contract CurveLP is BaseVault {
    address crv;
    IGauge gauge;
    IMinter minter;

    constructor() {
        _disableInitializers();
    }

    function __CurveLP__init(BaseVaultInitData calldata initData, address _gauge, address _minter, address _asset) internal initializer {
        __BaseVault__init(initData);
        gauge = IGauge(_gauge);
        minter = IMinter(_minter);
        crv = IMinter(_minter).token();

        IERC20(_asset).approve(_gauge, type(uint).max);
    }


    function _claim() internal override {
        minter.mint(address(gauge));
    }
    

    function rewardTokens() public view override returns (address[] memory) {
        uint256 rewardCount = gauge.reward_count();
        address[] memory _rewardTokens = new address[](rewardCount + 1);
        _rewardTokens[0] = crv;
        for (uint256 i; i < rewardCount; ++i) {
            _rewardTokens[i + 1] = gauge.reward_tokens(i);
        }
        return _rewardTokens;
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
