// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {AsyncVault, InitializeParams} from "./AsyncVault.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract RateVault is AsyncVault {
    address public multisig;

    constructor(
        InitializeParams memory params,
        address multisig_
    ) AsyncVault(params) {
        if (multisig_ == address(0)) revert Misconfigured();

        multisig = params.multisig;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 internal totalAssets_;
    uint256 public lastUpdateTime;

    /// @return Total amount of underlying `asset` token managed by vault. Delegates to adapter.
    function totalAssets() public view override returns (uint256) {
        return totalAssets_ + accruedYield();
    }

    function accruedYield() public view returns (uint256) {
        return
            (rate * (block.timestamp - lastUpdateTime) * totalAssets_) /
            365.25 days /
            1e18;
    }

    /*//////////////////////////////////////////////////////////////
                            YIELD RATE LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public rate;

    function setRate(uint256 rate_) external onlyOwner {
        rate = rate_;
    }

    modifier updateTotalAssets() {
        uint256 yieldEarned = accruedYield();

        if (yieldEarned > 0) {
            totalAssets_ = totalAssets_ + yieldEarned;
            lastUpdateTime = block.timestamp;
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            ERC-4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256) internal override {
        _takeFees();

        totalAssets_ -= assets;
    }

    function afterDeposit(uint256 assets, uint256) internal override {
        _takeFees();

        totalAssets_ += assets;

        SafeTransferLib.safeTransfer(asset, multisig, assets);
    }
}
