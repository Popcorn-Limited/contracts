// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20Metadata, ERC20, IERC20, Math} from "./BaseStrategy.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";

/**
 * @title   BaseStrategy
 * @author  RedVeil
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 *
 * The ERC4626 compliant base contract for all adapter contracts.
 * It allows interacting with an underlying protocol.
 * All specific interactions for the underlying protocol need to be overriden in the actual implementation.
 * The adapter can be initialized with a strategy that can perform additional operations. (Leverage, Compounding, etc.)
 */
abstract contract AnyConverter is BaseStrategy {
    using Math for uint256;

    address public yieldAsset;
    address[] internal tokens;

    IPriceOracle public oracle;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoDeposit_ Controls if `protocolDeposit` gets called on deposit
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function __AnyConverter_init(
        address asset_,
        address owner_,
        bool autoDeposit_,
        bytes memory strategyInitData_
    ) internal onlyInitializing {
        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        address oracle_;
        (yieldAsset, oracle_, slippage, floatRatio) = abi.decode(
            strategyInitData_,
            (address, address, uint256, uint256)
        );
        oracle = IPriceOracle(oracle_);

        tokens.push(asset_);
        tokens.push(yieldAsset);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Total amount of underlying `asset` token managed by adapter.
     * @dev Return assets held by adapter if paused.
     */
    function totalAssets() public view virtual override returns (uint256) {
        uint256 bal = IERC20(asset()).balanceOf(address(this));
        uint256 _totalReservedAssets = totalReservedAssets;
        uint256 yieldAssetBal = _totalAssets();

        if (bal <= _totalReservedAssets) return yieldAssetBal;
        return (bal - totalReservedAssets) + yieldAssetBal;
    }

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.
    function _totalAssets() internal view override returns (uint256) {
        uint256 yieldBal = IERC20(yieldAsset).balanceOf(address(this));
        uint256 _totalReservedYieldAssets = totalReservedYieldAssets;

        if (yieldBal <= _totalReservedYieldAssets) return 0;
        return
            oracle.getQuote(
                yieldBal - _totalReservedYieldAssets,
                yieldAsset,
                asset()
            );
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice deposit into the underlying protocol.
    function _protocolDeposit(
        uint256 assets,
        uint256 shares,
        bytes memory data
    ) internal override {
        // stay empty
    }

    /// @notice Withdraw from the underlying protocol.
    function _protocolWithdraw(
        uint256 assets,
        uint256 shares,
        bytes memory data
    ) internal override {
        // stay empty
    }

    /*//////////////////////////////////////////////////////////////
                        PUSH/PULL LOGIC
    //////////////////////////////////////////////////////////////*/

    event PushedFunds(uint256 yieldAssetsIn, uint256 assetsOut);
    event PulledFunds(uint256 assetsIn, uint256 yieldAssetsOut);

    error SlippageTooHigh();
    error NotEnoughFloat();

    function pushFunds(
        uint256 assets,
        bytes memory
    ) external override onlyKeeperOrOwner {
        // caching
        address _asset = asset();
        address _yieldAsset = yieldAsset;
        uint256 _floatRatio = floatRatio;

        uint256 ta = this.totalAssets();
        uint256 bal = IERC20(_asset).balanceOf(address(this));

        IERC20(_yieldAsset).transferFrom(msg.sender, address(this), assets);

        uint256 postTa = this.totalAssets();

        uint256 withdrawable = oracle.getQuote(assets, _yieldAsset, _asset);

        if (_floatRatio > 0) {
            uint256 float = ta.mulDiv(
                10_000 - _floatRatio,
                10_000,
                Math.Rounding.Floor
            );
            uint256 balAfterFloat = bal - float;
            if (balAfterFloat < withdrawable) withdrawable = balAfterFloat;
        } else {
            if (bal < withdrawable) withdrawable = bal;
        }

        if (
            postTa - withdrawable <
            ta.mulDiv(10_000 - slippage, 10_000, Math.Rounding.Floor)
        ) revert SlippageTooHigh();

        _reserveToken(assets, withdrawable, _asset, false);

        emit PushedFunds(assets, withdrawable);
    }

    function pullFunds(
        uint256 assets,
        bytes memory
    ) external override onlyKeeperOrOwner {
        // caching
        address _asset = asset();
        address _yieldAsset = yieldAsset;

        uint256 ta = this.totalAssets();

        IERC20(_asset).transferFrom(msg.sender, address(this), assets);

        uint256 postTa = this.totalAssets();

        uint256 withdrawable = oracle.getQuote(assets, _yieldAsset, _asset);

        if (
            postTa - withdrawable <
            ta.mulDiv(10_000 - slippage, 10_000, Math.Rounding.Floor)
        ) revert SlippageTooHigh();

        _reserveToken(assets, withdrawable, _yieldAsset, true);

        emit PulledFunds(assets, withdrawable);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    event SlippageProposed(uint256 slippage);
    event SlippageChanged(uint256 oldSlippage, uint256 newSlippage);
    event FloatRatioProposed(uint256 ratio);
    event FloatRatioChanged(uint256 oldRatio, uint256 newRatio);
    event UnlockTimeProposed(uint256 unlockTime);
    event UnlockTimeChanged(uint256 oldUnlockTime, uint256 newUnlockTime);

    error Misconfigured();

    struct ProposedChange {
        uint256 value;
        uint256 changeTime;
    }

    ProposedChange public proposedSlippage;
    uint256 public slippage;

    ProposedChange public proposedFloatRatio;
    uint256 public floatRatio;

    ProposedChange public proposedUnlockTime;
    uint256 public unlockTime;

    function proposeSlippage(uint256 slippage_) external onlyOwner {
        if (slippage_ > 10_000) revert Misconfigured();

        proposedSlippage = ProposedChange({
            value: slippage_,
            changeTime: block.timestamp + 3 days
        });

        emit SlippageProposed(slippage_);
    }

    function changeSlippage() external onlyOwner {
        ProposedChange memory _proposedSlippage = proposedSlippage;

        if (_proposedSlippage.changeTime == 0) revert Misconfigured();

        emit SlippageChanged(slippage, _proposedSlippage.value);

        slippage = _proposedSlippage.value;

        delete proposedSlippage;
    }

    function proposeFloatRatio(uint256 ratio_) external onlyOwner {
        if (ratio_ > 10_000) revert Misconfigured();

        proposedFloatRatio = ProposedChange({
            value: ratio_,
            changeTime: block.timestamp + 3 days
        });

        emit FloatRatioProposed(ratio_);
    }

    function changeFloatRatio() external onlyOwner {
        ProposedChange memory _proposedFloatRatio = proposedFloatRatio;

        if (_proposedFloatRatio.changeTime == 0) revert Misconfigured();

        emit FloatRatioChanged(slippage, _proposedFloatRatio.value);

        floatRatio = _proposedFloatRatio.value;

        delete proposedFloatRatio;
    }

    function proposeUnlockTime(uint256 unlockTime_) external onlyOwner {
        if (unlockTime_ < 1 days) revert Misconfigured();

        proposedUnlockTime = ProposedChange({
            value: unlockTime_,
            changeTime: block.timestamp + 3 days
        });

        emit UnlockTimeProposed(unlockTime_);
    }

    function changeUnlockTime() external onlyOwner {
        ProposedChange memory _proposedUnlockTime = proposedUnlockTime;

        if (_proposedUnlockTime.changeTime == 0) revert Misconfigured();

        emit UnlockTimeChanged(unlockTime, _proposedUnlockTime.value);

        unlockTime = _proposedUnlockTime.value;

        delete proposedUnlockTime;
    }


    /*//////////////////////////////////////////////////////////////
                            RESERVE LOGIC
    //////////////////////////////////////////////////////////////*/

    event ReserveClaimed(address user, address token, uint256 withdrawn);

    struct Reserved {
        uint256 unlockTime;
        uint256 deposited;
        uint256 withdrawable;
    }

    uint256 public totalReservedAssets;
    uint256 public totalReservedYieldAssets;

    mapping(address => mapping(address => Reserved[])) public reserved;

    function claimReserved(uint index) external {
        address _asset = asset();
        address _yieldAsset = yieldAsset;

        _claimReserved(_asset, _yieldAsset, index, false);
        _claimReserved(_yieldAsset, _asset, index, true);
    }

    function claimReserved() external {
        address _asset = asset();
        address _yieldAsset = yieldAsset;

        // since the array will be modified in each iteration, we need to cache the length
        // and just supply 0 as the index. The last element will be popped off the array
        // in each iteration.
        uint length = reserved[msg.sender][_asset].length;
        for (uint i = 0; i < length; ++i) {
            _claimReserved(_asset, _yieldAsset, 0, false);
        }

        length = reserved[msg.sender][_yieldAsset].length;
        for (uint i = 0; i < length; ++i) {
            _claimReserved(_yieldAsset, _asset, 0, true);
        }
    }

    function _claimReserved(
        address base,
        address quote,
        uint index,
        bool isYieldAsset
    ) internal {
        Reserved[] storage _reserved = reserved[msg.sender][base];
        if (_reserved[index].unlockTime < block.timestamp) {
            uint256 withdrawable = Math.min(
                oracle.getQuote(_reserved[index].deposited, base, quote),
                _reserved[index].withdrawable
            );

            if (withdrawable > 0) {
                _reserved[index] = _reserved[_reserved.length - 1];
                _reserved.pop();

                if (isYieldAsset) {
                    totalReservedYieldAssets -= withdrawable;
                } else {
                    totalReservedAssets -= withdrawable;
                }

                IERC20(base).transfer(msg.sender, withdrawable);
            }
            emit ReserveClaimed(msg.sender, base, _reserved[index].withdrawable);
        }
    }

    function _reserveToken(
        uint256 amount,
        uint256 withdrawable,
        address token,
        bool isYieldAsset
    ) internal {
        Reserved[] storage _reserved = reserved[msg.sender][token];

        _reserved.push(Reserved({
            deposited: amount,
            withdrawable: withdrawable,
            unlockTime: block.timestamp + unlockTime
        }));

        if (isYieldAsset) {
            totalReservedYieldAssets += amount;
        } else {
            totalReservedAssets += amount;
        }
    }
}
