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
    function __AnyConverter_init(address asset_, address owner_, bool autoDeposit_, bytes memory strategyInitData_)
        internal
        onlyInitializing
    {
        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        address oracle_;
        (yieldAsset, oracle_, slippage, floatRatio) =
            abi.decode(strategyInitData_, (address, address, uint256, uint256));
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
        // yieldAssetBal is the total amount of yieldAssets that are held by the contract
        // priced in the underlying asset token
        uint256 yieldAssetBal = _totalAssets();

        if (bal + yieldAssetBal <= _totalReservedAssets) return 0;
        return (bal + yieldAssetBal - totalReservedAssets);
    }

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.
    function _totalAssets() internal view override returns (uint256) {
        uint256 yieldBal = IERC20(yieldAsset).balanceOf(address(this));
        uint256 _totalReservedYieldAssets = totalReservedYieldAssets;

        if (yieldBal <= _totalReservedYieldAssets) return 0;
        return oracle.getQuote(yieldBal - _totalReservedYieldAssets, yieldAsset, asset());
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice deposit into the underlying protocol.
    function _protocolDeposit(uint256 assets, uint256 shares, bytes memory data) internal override {
        // stay empty
    }

    /// @notice Withdraw from the underlying protocol.
    function _protocolWithdraw(uint256 assets, uint256 shares, bytes memory data) internal override {
        // stay empty
    }

    /*//////////////////////////////////////////////////////////////
                        PUSH/PULL LOGIC
    //////////////////////////////////////////////////////////////*/

    event PushedFunds(uint256 yieldAssetsIn, uint256 assetsOut);
    event PulledFunds(uint256 assetsIn, uint256 yieldAssetsOut);

    error SlippageTooHigh();
    error NotEnoughFloat();

    function pushFunds(uint256 yieldAssets, bytes memory) external override onlyKeeperOrOwner {
        // caching
        address _asset = asset();
        address _yieldAsset = yieldAsset;
        uint256 _floatRatio = floatRatio;

        uint256 ta = totalAssets();
        // TODO: should take into account the reserved assets
        uint256 bal = IERC20(_asset).balanceOf(address(this));

        IERC20(_yieldAsset).transferFrom(msg.sender, address(this), yieldAssets);

        uint256 withdrawable = oracle.getQuote(yieldAssets, _yieldAsset, _asset);

        // TODO: we should probably revert if we don't have enough funds
        // to cover the withdrawable amount
        if (_floatRatio > 0) {
            uint256 float = ta.mulDiv(10_000 - _floatRatio, 10_000, Math.Rounding.Floor);
            uint256 balAfterFloat = bal - float;
            if (balAfterFloat < withdrawable) withdrawable = balAfterFloat;
        } else {
            if (bal < withdrawable) withdrawable = bal;
        }

        _reserveToken(yieldAssets, withdrawable, _yieldAsset, false);
        uint256 postTa = totalAssets();

        if (postTa < ta.mulDiv(10_000 - slippage, 10_000, Math.Rounding.Floor)) revert SlippageTooHigh();

        emit PushedFunds(yieldAssets, withdrawable);
    }

    function pullFunds(uint256 assets, bytes memory) external override onlyKeeperOrOwner {
        // caching
        address _asset = asset();
        address _yieldAsset = yieldAsset;

        uint256 ta = totalAssets();

        IERC20(_asset).transferFrom(msg.sender, address(this), assets);

        uint256 withdrawable = oracle.getQuote(assets, _asset, _yieldAsset);
        _reserveToken(assets, withdrawable, _asset, true);

        uint256 postTa = totalAssets();

        if (postTa < ta.mulDiv(10_000 - slippage, 10_000, Math.Rounding.Floor)) revert SlippageTooHigh();

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
    uint256 public unlockTime = 1 days;

    function proposeSlippage(uint256 slippage_) external onlyOwner {
        if (slippage_ > 10_000) revert Misconfigured();

        proposedSlippage = ProposedChange({value: slippage_, changeTime: block.timestamp + 3 days});

        emit SlippageProposed(slippage_);
    }

    function changeSlippage() external onlyOwner {
        ProposedChange memory _proposedSlippage = proposedSlippage;

        if (_proposedSlippage.changeTime == 0 || block.timestamp > _proposedSlippage.changeTime) revert Misconfigured();

        emit SlippageChanged(slippage, _proposedSlippage.value);

        slippage = _proposedSlippage.value;

        delete proposedSlippage;
    }

    function proposeFloatRatio(uint256 ratio_) external onlyOwner {
        if (ratio_ > 10_000) revert Misconfigured();

        proposedFloatRatio = ProposedChange({value: ratio_, changeTime: block.timestamp + 3 days});

        emit FloatRatioProposed(ratio_);
    }

    function changeFloatRatio() external onlyOwner {
        ProposedChange memory _proposedFloatRatio = proposedFloatRatio;

        if (_proposedFloatRatio.changeTime == 0 || block.timestamp > _proposedFloatRatio.changeTime) {
            revert Misconfigured();
        }

        emit FloatRatioChanged(slippage, _proposedFloatRatio.value);

        floatRatio = _proposedFloatRatio.value;

        delete proposedFloatRatio;
    }

    function proposeUnlockTime(uint256 unlockTime_) external onlyOwner {
        proposedUnlockTime = ProposedChange({value: unlockTime_, changeTime: block.timestamp + 3 days});

        emit UnlockTimeProposed(unlockTime_);
    }

    function changeUnlockTime() external onlyOwner {
        ProposedChange memory _proposedUnlockTime = proposedUnlockTime;

        if (_proposedUnlockTime.changeTime == 0 || block.timestamp > _proposedUnlockTime.changeTime) {
            revert Misconfigured();
        }

        emit UnlockTimeChanged(unlockTime, _proposedUnlockTime.value);

        unlockTime = _proposedUnlockTime.value;

        delete proposedUnlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                            RESERVE LOGIC
    //////////////////////////////////////////////////////////////*/

    event ReserveClaimed(address user, address token, uint256 withdrawn);
    // we don't emit the block number because that's already part of the event log
    // e.g. see https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getlogs
    event ReserveAdded(
        address indexed user, address indexed asset, uint256 unlockTime, uint256 amount, uint256 withdrawable
    );

    struct Reserved {
        uint256 unlockTime;
        uint256 deposited;
        uint256 withdrawable;
    }

    uint256 public totalReservedAssets;
    uint256 public totalReservedYieldAssets;

    // we only allow 1 reserve per block so we can use that as the
    // primary key to differentiate between multiple reserves.
    //
    // user address => asset address => block number => Reserved
    mapping(address => mapping(address => mapping(uint256 => Reserved))) public reserved;

    function claimReserved(uint256 blockNumber) external {
        address _asset = asset();
        address _yieldAsset = yieldAsset;

        _claimReserved(_asset, _yieldAsset, blockNumber, true);
        _claimReserved(_yieldAsset, _asset, blockNumber, false);
    }

    function _claimReserved(address base, address quote, uint256 blockNumber, bool isYieldAsset) internal {
        Reserved memory _reserved = reserved[msg.sender][base][blockNumber];
        if (_reserved.unlockTime != 0 && _reserved.unlockTime < block.timestamp) {
            // if the assets value went down after the keeper reserved the funds,
            // we want to use the new favorable quote.
            // If the assets value went up, we want to use the old favorable quote.
            uint256 withdrawable = Math.min(oracle.getQuote(_reserved.deposited, base, quote), _reserved.withdrawable);

            if (withdrawable > 0) {
                delete reserved[msg.sender][base][blockNumber];

                if (isYieldAsset) {
                    totalReservedYieldAssets -= _reserved.withdrawable;
                } else {
                    totalReservedAssets -= _reserved.withdrawable;
                }

                IERC20(quote).transfer(msg.sender, withdrawable);
            }
            emit ReserveClaimed(msg.sender, base, _reserved.withdrawable);
        }
    }

    function _reserveToken(uint256 amount, uint256 withdrawable, address token, bool isYieldAsset) internal {
        if (reserved[msg.sender][token][block.number].deposited > 0) {
            revert("Already reserved");
        }

        uint256 _unlockTime = block.timestamp + unlockTime;
        reserved[msg.sender][token][block.number] =
            Reserved({deposited: amount, withdrawable: withdrawable, unlockTime: _unlockTime});

        if (isYieldAsset) {
            totalReservedYieldAssets += withdrawable;
        } else {
            totalReservedAssets += withdrawable;
        }

        emit ReserveAdded(msg.sender, token, _unlockTime, amount, withdrawable);
    }

    /*//////////////////////////////////////////////////////////////
                            RESERVE LOGIC
    //////////////////////////////////////////////////////////////*/

    function rescueToken(address token) external onlyOwner {
        for (uint256 i; i < tokens.length; i++) {
            if (tokens[i] == token) revert Misconfigured();
        }

        uint256 bal = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(owner, bal);
    }
}
