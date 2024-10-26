// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseStrategy, IERC20Metadata, ERC20, IERC20, Math} from "src/strategies/BaseStrategy.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";
import {BytesLib} from "bitlib/BytesLib.sol";

struct CallStruct {
    address target;
    bytes data;
}

struct PendingTarget {
    address target;
    bytes4 selector;
    bool allowed;
}

struct ProposedChange {
    uint256 value;
    uint256 changeTime;
}

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
abstract contract AnyConverterV2 is BaseStrategy {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using BytesLib for bytes;

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

        (
            address yieldToken_,
            address oracle_,
            uint256 slippage_,
            PendingTarget[] memory pendingTargets_,
            CallStruct[] memory pendingAllowances_
        ) = abi.decode(
                strategyInitData_,
                (address, address, uint256, PendingTarget[], CallStruct[])
            );

        if (yieldToken_ == address(0)) revert Misconfigured();
        if (oracle_ == address(0)) revert Misconfigured();

        yieldToken = yieldToken_;
        tokens.push(asset_);
        tokens.push(yieldToken);

        oracle = IPriceOracle(oracle_);
        slippage = slippage_;

        for (uint256 i; i < pendingTargets.length; i++) {
            isAllowed[pendingTargets[i].target][
                pendingTargets[i].selector
            ] = pendingTargets[i].allowed;

            emit TargetUpdated(
                pendingTargets[i].target,
                pendingTargets[i].selector,
                pendingTargets[i].allowed
            );
        }

        for (uint256 i; i < pendingAllowances.length; i++) {
            pendingAllowances[i].target.call(pendingAllowances[i].data);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Total amount of underlying `asset` token managed by adapter.
     * @dev Return assets held by adapter if paused.
     */
    function _totalAssets() internal view virtual override returns (uint256) {
        return
            oracle.getQuote(
                IERC20(yieldToken).balanceOf(address(this)),
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

    /// @notice Convert assets to yieldTokens
    function pushFunds(
        uint256,
        bytes memory data
    ) external virtual override onlyKeeperOrOwner {
        uint256[6] memory stats = _execute(data);

        // Total assets should stay the same or increase (with slippage)
        if (
            stats[3] <
            stats[0].mulDiv(10_000 - slippage, 10_000, Math.Rounding.Ceil)
        ) revert("Total assets decreased");
        // Asset balance should stay the same or decrease
        if (stats[4] >= stats[1]) revert("Asset balance increased");
        // YieldToken balance should stay increase
        if (stats[5] < stats[2]) revert("Yield token balance decreased");

        emit PushedFunds(stats[5] - stats[2], stats[1] - stats[4]);
    }

    /// @notice Convert yieldTokens to assets
    function pullFunds(
        uint256,
        bytes memory data
    ) external virtual override onlyKeeperOrOwner {
        uint256[6] memory stats = _execute(data);

        // Total assets should stay the same or increase (with slippage)
        if (
            stats[3] <
            stats[0].mulDiv(10_000 - slippage, 10_000, Math.Rounding.Ceil)
        ) revert("Total assets decreased");

        // YieldToken balance should stay the same or decrease
        if (stats[5] >= stats[2]) revert("YieldToken balance increased");

        // Asset balance should increase
        if (stats[4] < stats[1]) revert("Asset balance decreased");

        emit PulledFunds(stats[4] - stats[1], stats[2] - stats[5]);
    }

    function _execute(
        bytes memory data
    ) internal virtual returns (uint256[6] memory) {
        // caching
        address _asset = asset();
        address _yieldToken = yieldToken;

        uint256 preTotalAssets = totalAssets();
        uint256 preAssetBalance = IERC20(_asset).balanceOf(address(this));
        uint256 preYieldTokenBalance = IERC20(_yieldToken).balanceOf(
            address(this)
        );

        CallStruct[] memory calls = abi.decode(data, (CallStruct[]));
        for (uint256 i; i < calls.length; i++) {
            if (!isAllowed[calls[i].target][bytes4(calls[i].data)])
                revert("Not allowed");

            (bool success, ) = calls[i].target.call(calls[i].data);
            if (!success) revert("Call failed");
        }

        uint256 postTotalAssets = totalAssets();
        uint256 postAssetBalance = IERC20(_asset).balanceOf(address(this));
        uint256 postYieldTokenBalance = IERC20(_yieldToken).balanceOf(
            address(this)
        );
        return (
            [
                preTotalAssets,
                preAssetBalance,
                preYieldTokenBalance,
                postTotalAssets,
                postAssetBalance,
                postYieldTokenBalance
            ]
        );
    }

    function execute(bytes memory data) external virtual onlyKeeperOrOwner {
        uint256[6] memory stats = _execute(data);

        // Total assets should stay the same or increase (with slippage)
        if (
            stats[3] <
            stats[0].mulDiv(10_000 - slippage, 10_000, Math.Rounding.Ceil)
        ) revert("Total assets decreased");
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    event SlippageProposed(uint256 slippage);
    event SlippageChanged(uint256 oldSlippage, uint256 newSlippage);

    error Misconfigured();

    ProposedChange public proposedSlippage;
    uint256 public slippage;

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

    /*//////////////////////////////////////////////////////////////
                        SET TARGET LOGIC
    //////////////////////////////////////////////////////////////*/

    event TargetProposed(address target, bytes4 selector, bool isAllowed);
    event TargetUpdated(address target, bytes4 selector, bool isAllowed);

    PendingTarget[] public pendingTargets;
    uint256 public pendingTargetTime;
    mapping(address => mapping(bytes4 => bool)) public isAllowed;

    function proposeTargets(
        PendingTarget[] calldata targets
    ) external onlyOwner {
        for (uint256 i; i < targets.length; i++) {
            pendingTargets.push(targets[i]);

            emit TargetProposed(
                targets[i].target,
                targets[i].selector,
                targets[i].allowed
            );
        }
        pendingTargetTime = block.timestamp + 3 days;
    }

    function updateTargets() external onlyOwner {
        if (pendingTargetTime == 0 || pendingTargetTime > block.timestamp)
            revert Misconfigured();

        for (uint256 i; i < pendingTargets.length; i++) {
            isAllowed[pendingTargets[i].target][
                pendingTargets[i].selector
            ] = pendingTargets[i].allowed;

            emit TargetUpdated(
                pendingTargets[i].target,
                pendingTargets[i].selector,
                pendingTargets[i].allowed
            );
        }

        delete pendingTargets;
        delete pendingTargetTime;
    }

    function getProposedTargets()
        external
        view
        returns (uint256, PendingTarget[] memory)
    {
        return (pendingTargetTime, pendingTargets);
    }

    /*//////////////////////////////////////////////////////////////
                            ALLOWANCE LOGIC
    //////////////////////////////////////////////////////////////*/

    CallStruct[] public pendingAllowances;
    uint256 public pendingAllowanceTime;

    event AllowanceProposed(address target, bytes data);

    function proposeAllowances(
        CallStruct[] calldata allowanceCalls
    ) external onlyOwner {
        for (uint256 i; i < allowanceCalls.length; i++) {
            pendingAllowances.push(allowanceCalls[i]);

            emit AllowanceProposed(
                allowanceCalls[i].target,
                allowanceCalls[i].data
            );
        }
        pendingAllowanceTime = block.timestamp + 3 days;
    }

    function updateAllowances() external onlyOwner {
        if (pendingAllowanceTime == 0 || pendingAllowanceTime > block.timestamp)
            revert Misconfigured();

        for (uint256 i; i < pendingAllowances.length; i++) {
            pendingAllowances[i].target.call(pendingAllowances[i].data);
        }

        delete pendingAllowances;
        delete pendingAllowanceTime;
    }

    function getProposedAllowances()
        external
        view
        returns (uint256, CallStruct[] memory)
    {
        return (pendingAllowanceTime, pendingAllowances);
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
