// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
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
    using SafeERC20 for IERC20;

    address public yieldToken;
    address[] public tokens;

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
        (yieldToken, oracle_, slippage, floatRatio) = abi.decode(
            strategyInitData_,
            (address, address, uint256, uint256)
        );
        oracle = IPriceOracle(oracle_);

        tokens.push(asset_);
        tokens.push(yieldToken);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Total amount of underlying `asset` token managed by adapter.
     * @dev Return assets held by adapter if paused.
     */
    function totalAssets() public view override returns (uint256) {
        return _totalAssets();
    }

    function _totalAssets() internal view override returns (uint256) {
        uint256 bal = IERC20(asset()).balanceOf(address(this));
        uint256 _totalReservedAssets = totalReservedAssets;
        // yieldTokenBal is the total amount of yieldTokens that are held by the contract
        // priced in the underlying asset token
        uint256 yieldTokenBal = _totalYieldTokenInAssets();

        if (bal + yieldTokenBal <= _totalReservedAssets) return 0;
        return (bal + yieldTokenBal - totalReservedAssets);
    }

    function _totalYieldTokenInAssets() internal view returns (uint256) {
        uint256 yieldBal = IERC20(yieldToken).balanceOf(address(this));
        uint256 _totalReservedYieldTokens = totalReservedYieldTokens;

        if (yieldBal <= _totalReservedYieldTokens) return 0;
        return
            oracle.getQuote(
                yieldBal - _totalReservedYieldTokens,
                yieldToken,
                asset()
            );
    }

    function convertToUnderlyingShares(
        uint256 assets,
        uint256 shares
    ) public view override returns (uint256) {
        revert();
    }

    function rewardTokens()
        external
        view
        virtual
        override
        returns (address[] memory)
    {
        revert();
    }

    function getFloat() internal view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - totalReservedAssets;
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

    event PushedFunds(uint256 yieldTokensIn, uint256 assetsOut);
    event PulledFunds(uint256 assetsIn, uint256 yieldTokensOut);

    error SlippageTooHigh();
    error NotEnoughFloat();
    error BalanceTooLow();

    function claim() internal override returns (bool success) {
        revert();
    }

    function harvest(bytes memory data) external virtual override {
        revert();
    }

    function pushFunds(
        uint256 yieldTokens,
        bytes memory
    ) external override onlyKeeperOrOwner whenNotPaused {
        // caching
        address _asset = asset();
        address _yieldToken = yieldToken;
        uint256 _floatRatio = floatRatio;

        uint256 ta = totalAssets();
        uint256 bal = IERC20(_asset).balanceOf(address(this)) -
            totalReservedAssets;

        IERC20(_yieldToken).safeTransferFrom(
            msg.sender,
            address(this),
            yieldTokens
        );

        // raise it by slippage
        yieldTokens = yieldTokens.mulDiv(
            10_000,
            10_000 - slippage,
            Math.Rounding.Floor
        );
        uint256 withdrawable = oracle.getQuote(
            yieldTokens,
            _yieldToken,
            _asset
        );

        // we revert if:
        // 1. we don't have enough funds to cover the withdrawable amount
        // 2. we don't have enough float after the withdrawal (if floatRatio > 0)
        if (_floatRatio > 0) {
            uint256 float = ta.mulDiv(_floatRatio, 10_000, Math.Rounding.Floor);
            if (float > bal) {
                revert NotEnoughFloat();
            } else {
                uint256 balAfterFloat = bal - float;
                if (balAfterFloat < withdrawable) revert BalanceTooLow();
            }
        } else {
            if (bal < withdrawable) revert BalanceTooLow();
        }

        _reserveToken(yieldTokens, withdrawable, _yieldToken, false);

        emit PushedFunds(yieldTokens, withdrawable);
    }

    function pullFunds(
        uint256 assets,
        bytes memory
    ) external override onlyKeeperOrOwner whenNotPaused {
        // caching
        address _asset = asset();
        address _yieldToken = yieldToken;

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), assets);

        // raise it by slippage
        assets = assets.mulDiv(
            10_000,
            10_000 - slippage,
            Math.Rounding.Floor
        );
        uint256 withdrawable = oracle.getQuote(assets, _asset, _yieldToken);
        _reserveToken(assets, withdrawable, _asset, true);

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
    uint256 public unlockTime = 1;

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

        if (
            _proposedSlippage.changeTime == 0 ||
            _proposedSlippage.changeTime > block.timestamp
        ) revert Misconfigured();

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

        if (
            _proposedFloatRatio.changeTime == 0 ||
            _proposedFloatRatio.changeTime > block.timestamp
        ) {
            revert Misconfigured();
        }

        emit FloatRatioChanged(slippage, _proposedFloatRatio.value);

        floatRatio = _proposedFloatRatio.value;

        delete proposedFloatRatio;
    }

    function proposeUnlockTime(uint256 unlockTime_) external onlyOwner {
        proposedUnlockTime = ProposedChange({
            value: unlockTime_,
            changeTime: block.timestamp + 3 days
        });

        emit UnlockTimeProposed(unlockTime_);
    }

    function changeUnlockTime() external onlyOwner {
        ProposedChange memory _proposedUnlockTime = proposedUnlockTime;

        if (
            _proposedUnlockTime.changeTime == 0 ||
            _proposedUnlockTime.changeTime > block.timestamp
        ) {
            revert Misconfigured();
        }

        emit UnlockTimeChanged(unlockTime, _proposedUnlockTime.value);

        unlockTime = _proposedUnlockTime.value;

        delete proposedUnlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                            RESERVE LOGIC
    //////////////////////////////////////////////////////////////*/

    event ReserveClaimed(
        address user,
        address token,
        uint256 blockNumber,
        uint256 withdrawn
    );
    // we don't emit the block number because that's already part of the event log
    // e.g. see https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getlogs
    event ReserveAdded(
        address indexed user,
        address indexed asset,
        uint256 blockNumber,
        uint256 unlockTime,
        uint256 amount,
        uint256 withdrawable
    );

    struct Reserved {
        uint256 unlockTime;
        uint256 deposited;
        uint256 withdrawable;
    }

    uint256 public totalReservedAssets;
    uint256 public totalReservedYieldTokens;

    // we only allow 1 reserve per block so we can use that as the
    // primary key to differentiate between multiple reserves.
    //
    // user address => asset address => block number => Reserved
    mapping(address => mapping(address => mapping(uint256 => Reserved)))
        public reserved;

    function claimReserved(uint256 blockNumber, bool isyieldToken) external {
        address base = isyieldToken ? asset() : yieldToken;
        address quote = isyieldToken ? yieldToken : asset();

        Reserved memory _reserved = reserved[msg.sender][base][blockNumber];
        if (
            _reserved.unlockTime != 0 && _reserved.unlockTime < block.timestamp
        ) {
            // if the assets value went down after the keeper reserved the funds,
            // we want to use the new favorable quote.
            // If the assets value went up, we want to use the old favorable quote.
            uint256 withdrawable = Math.min(
                oracle.getQuote(_reserved.deposited, base, quote),
                _reserved.withdrawable
            );

            if (withdrawable > 0) {
                delete reserved[msg.sender][base][blockNumber];

                if (isyieldToken) {
                    totalReservedYieldTokens -= _reserved.withdrawable;
                } else {
                    totalReservedAssets -= _reserved.withdrawable;
                }

                IERC20(quote).safeTransfer(msg.sender, withdrawable);
                emit ReserveClaimed(
                    msg.sender,
                    base,
                    blockNumber,
                    _reserved.withdrawable
                );
            } else {
                revert("Nothing to claim");
            }
        } else {
            revert("Nothing to claim");
        }
    }

    function _reserveToken(
        uint256 amount,
        uint256 withdrawable,
        address token,
        bool isyieldToken
    ) internal {
        if (reserved[msg.sender][token][block.number].deposited > 0) {
            revert("Already reserved");
        }

        uint256 _unlockTime = block.timestamp + unlockTime;
        reserved[msg.sender][token][block.number] = Reserved({
            deposited: amount,
            withdrawable: withdrawable,
            unlockTime: _unlockTime
        });

        if (isyieldToken) {
            totalReservedYieldTokens += withdrawable;
        } else {
            totalReservedAssets += withdrawable;
        }

        emit ReserveAdded(
            msg.sender,
            token,
            block.number,
            _unlockTime,
            amount,
            withdrawable
        );
    }

    /*//////////////////////////////////////////////////////////////
                            RESERVE LOGIC
    //////////////////////////////////////////////////////////////*/

    function rescueToken(address token) external onlyOwner {
        for (uint256 i; i < tokens.length; i++) {
            if (tokens[i] == token) revert Misconfigured();
        }

        uint256 bal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(owner, bal);
    }
}
