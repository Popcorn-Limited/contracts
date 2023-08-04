pragma solidity ^0.8.15;

import {IGauge, IMinter} from "../../adapter/curve/ICurve.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/interfaces/IERC20Metadata.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC4626Upgradeable as IERC4626 } from "openzeppelin-contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract CurveLP is Initializable {
    using SafeERC20 for IERC20;

    address crv;
    IERC20 asset;
    IGauge gauge;
    IMinter minter;
    address vault;

    address[] internal rewardTokens;

    modifier onlyVault() {
        require(msg.sender == vault);
        _;
    }

    function __CurveLP__init(address _vault, address _gauge, address _minter) internal onlyInitializing {
        gauge = IGauge(_gauge);
        minter = IMinter(_minter);
        crv = IMinter(_minter).token();

        vault = _vault;

        asset = IERC20(IERC4626(_vault).asset());
        IERC20(asset).approve(_gauge, type(uint).max);

        updateRewardTokens();
    }


    function _claim() internal {
        minter.mint(address(gauge));
    }
    
    /// @dev used to retrieve the current reward tokens in case they've changed.
    /// callable by anyone
    function updateRewardTokens() public {
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
    
    function deposit(uint amount) external onlyVault {
        _deposit(amount);
    }

    function _deposit(uint amount) internal {
        gauge.deposit(amount);
    }

    function withdraw(address to, uint amount) external onlyVault {
        gauge.withdraw(amount);
        asset.safeTransfer(to, amount);
    }

    function totalAssets() external view returns (uint) {
        return gauge.balanceOf(address(this));
    }
}
