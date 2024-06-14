// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20Metadata, ERC20, IERC20, Math} from "./BaseStrategy.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";

struct ProposedChange {
    uint256 value;
    uint256 changeTime;
}

struct ProposedRouter {
    address value;
    uint256 changeTime;
}

abstract contract EnsoConverter is BaseStrategy {
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
    function __EnsoConverter_init(
        address asset_,
        address owner_,
        bool autoDeposit_,
        bytes memory strategyInitData_
    ) internal onlyInitializing {
        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        address oracle_;
        (yieldAsset, ensoRouter, oracle_, slippage, floatRatio) = abi.decode(
            strategyInitData_,
            (address, address, address, uint256, uint256)
        );
        oracle = IPriceOracle(oracle_);

        tokens.push(asset_);
        tokens.push(yieldAsset);

        _approveTokens(tokens, ensoRouter, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.
    function _totalAssets() internal view override returns (uint256) {
        return
            oracle.getQuote(
                IERC20(yieldAsset).balanceOf(address(this)),
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

    error SlippageTooHigh();
    error NotEnoughFloat();

    function pushFunds(
        uint256,
        bytes memory data
    ) external override onlyKeeperOrOwner {
        _pushViaEnso(data);
    }

    function _pushViaEnso(bytes memory data) internal {
        // caching
        address _asset = asset();
        uint256 _floatRatio = floatRatio;

        uint256 ta = this.totalAssets();
        uint256 bal = IERC20(_asset).balanceOf(address(this));

        (bool success, ) = ensoRouter.call(data);
        if (success) {
            if (
                this.totalAssets() <
                ta.mulDiv(10_000 - slippage, 10_000, Math.Rounding.Floor)
            ) revert SlippageTooHigh();

            if (_floatRatio > 0) {
                if (
                    IERC20(_asset).balanceOf(address(this)) <
                    ta.mulDiv(10_000 - _floatRatio, 10_000, Math.Rounding.Floor)
                ) revert NotEnoughFloat();
            }
        }
    }

    function pullFunds(
        uint256,
        bytes memory data
    ) external override onlyKeeperOrOwner {
        _pullViaEnso(data);
    }

    function _pullViaEnso(bytes memory data) internal {
        uint256 ta = this.totalAssets();

        (bool success, ) = ensoRouter.call(data);
        if (success) {
            if (
                this.totalAssets() <
                ta.mulDiv(10_000 - slippage, 10_000, Math.Rounding.Floor)
            ) revert SlippageTooHigh();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    event SlippageProposed(uint256 slippage);
    event SlippageChanged(uint256 oldSlippage, uint256 newSlippage);
    event FloatRatioProposed(uint256 ratio);
    event FloatRatioChanged(uint256 oldRatio, uint256 newRatio);
    event EnsoRouterProposed(address router);
    event EnsoRouterChanged(address oldRouter, address newRouter);

    error Misconfigured();

    ProposedChange public proposedSlippage;
    uint256 public slippage;

    ProposedChange public proposedFloatRatio;
    uint256 public floatRatio;

    ProposedRouter public proposedEnsoRouter;
    address public ensoRouter;

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

    function proposeEnsoRouter(address ensoRouter_) external onlyOwner {
        if (ensoRouter_ == ensoRouter) revert Misconfigured();

        proposedEnsoRouter = ProposedRouter({
            value: ensoRouter_,
            changeTime: block.timestamp + 3 days
        });

        emit EnsoRouterProposed(ensoRouter_);
    }

    function changeEnsoRouter() external virtual onlyOwner {
        ProposedRouter memory _proposedEnsoRouter = proposedEnsoRouter;

        if (_proposedEnsoRouter.changeTime == 0) revert Misconfigured();

        _approveTokens(tokens, ensoRouter, 0);
        _approveTokens(tokens, _proposedEnsoRouter.value, type(uint256).max);

        emit EnsoRouterChanged(ensoRouter, _proposedEnsoRouter.value);

        ensoRouter = _proposedEnsoRouter.value;

        delete proposedFloatRatio;
    }

    function _approveTokens(
        address[] memory tokens_,
        address spender,
        uint256 amount
    ) internal {
        uint256 len = tokens_.length;
        if (len > 0) {
            for (uint256 i; i < len; ) {
                IERC20(tokens_[i]).approve(spender, amount);

                unchecked {
                    ++i;
                }
            }
        }
    }
}
