// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {AnyCompounderNaiveV2, AnyConverterV2, CallStruct, PendingCallAllowance, IERC20Metadata, ERC20, IERC20, Math} from "./AnyCompounderNaiveV2.sol";
import {ILBT} from "src/interfaces/external/lfj/ILBT.sol";
import {BytesLib} from "bitlib/BytesLib.sol";

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
contract AnyLBTManager is AnyCompounderNaiveV2 {
    using Math for uint256;
    using BytesLib for bytes;

    address public tokenX;
    address public tokenY;
    uint24[] public depositIds;

    event DepositIdSet(uint256 depositId);

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoDeposit_ Controls if `protocolDeposit` gets called on deposit
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function initialize(
        address asset_,
        address owner_,
        bool autoDeposit_,
        bytes memory strategyInitData_
    ) external initializer {
        __AnyConverter_init(asset_, owner_, autoDeposit_, strategyInitData_);
        tokenX = ILBT(yieldToken).getTokenX();
        tokenY = ILBT(yieldToken).getTokenY();
    }

    /**
     * @notice Total amount of underlying `asset` token managed by adapter.
     * @dev Return assets held by adapter if paused.
     */
    function _totalAssets()
        internal
        view
        override
        returns (uint256 totalAssets)
    {
        uint24 activeId = ILBT(yieldToken).getActiveId();

        uint256 amountY = 0;
        uint256 amountX = 0;
        for (uint256 i = 0; i < depositIds.length; i++) {
            uint256 balance = ILBT(yieldToken).balanceOf(
                address(this),
                depositIds[i]
            );
            (uint128 reserveX, uint128 reserveY) = ILBT(yieldToken).getBin(
                depositIds[i]
            );
            uint256 totalSupply = ILBT(yieldToken).totalSupply(depositIds[i]);

            if (depositIds[i] <= activeId) {
                amountY += (balance * uint256(reserveY)) / totalSupply;
            }

            if (depositIds[i] >= activeId) {
                amountX += (balance * uint256(reserveX)) / totalSupply;
            }
        }
        address _tokenX = tokenX;
        address _tokenY = tokenY;
        address _asset = asset();

        if (_tokenX == _asset) {
            totalAssets = amountX;
        } else {
            totalAssets = oracle.getQuote(
                IERC20(_tokenX).balanceOf(address(this)) + amountX,
                _tokenX,
                _asset
            );
        }

        if (_tokenY == _asset) {
            totalAssets += amountY;
        } else {
            totalAssets += oracle.getQuote(
                IERC20(_tokenY).balanceOf(address(this)) + amountY,
                _tokenY,
                _asset
            );
        }

        uint256 _outstandingAllowance = outstandingAllowance;
        if (_outstandingAllowance > totalAssets) return 0;
        totalAssets -= _outstandingAllowance;
    }

    function setDepositIds(uint24[] memory ids) external onlyKeeperOrOwner {
        delete depositIds;

        for (uint256 i = 0; i < ids.length; i++) {
            depositIds.push(ids[i]);
            emit DepositIdSet(ids[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @notice Convert assets to yieldTokens
    function pushFunds(
        uint256,
        bytes memory data
    ) external override onlyKeeperOrOwner {
        uint256[6] memory stats = _execute(data);

        // Total assets should stay the same or increase (with slippage)
        if (
            stats[1] <
            stats[0].mulDiv(10_000 - slippage, 10_000, Math.Rounding.Ceil)
        ) revert("Total assets decreased");

        emit PushedFunds(0, 0);
    }

    /// @notice Convert yieldTokens to assets
    function pullFunds(
        uint256,
        bytes memory data
    ) external override onlyKeeperOrOwner {
        uint256[6] memory stats = _execute(data);

        // Total assets should stay the same or increase (with slippage)
        if (
            stats[1] <
            stats[0].mulDiv(10_000 - slippage, 10_000, Math.Rounding.Ceil)
        ) revert("Total assets decreased");

        emit PulledFunds(0, 0);
    }

    event LogUint(string, uint);

    function _execute(
        bytes memory data
    ) internal override returns (uint256[6] memory) {
        // caching
        address _asset = asset();
        address _yieldToken = yieldToken;

        uint256 preTotalAssets = totalAssets();

        CallStruct[] memory calls = abi.decode(data, (CallStruct[]));
        CallStruct[] memory allowanceCalls = new CallStruct[](calls.length);
        for (uint256 i; i < calls.length; i++) {
            if (!isAllowed[calls[i].target][bytes4(calls[i].data)])
                revert("Not allowed");

            if (bytes4(calls[i].data) == APPROVE_SELECTOR) {
                (address to, ) = abi.decode(
                    calls[i].data.slice(4, calls[i].data.length - 4),
                    (address, uint256)
                );
                allowanceCalls[i] = CallStruct({
                    target: calls[i].target,
                    data: abi.encodeWithSelector(
                        bytes4(keccak256("allowance(address,address)")),
                        address(this),
                        to
                    )
                });
            }

            (bool success, ) = calls[i].target.call(calls[i].data);
            if (!success) revert("Call failed");
        }

        uint256 outstandingAllowance;
        for (uint256 i; i < allowanceCalls.length; i++) {
            if (allowanceCalls[i].target != address(0)) {
                (bool success, bytes memory result) = allowanceCalls[i]
                    .target
                    .call(allowanceCalls[i].data);
                if (!success) revert("Call failed");

                outstandingAllowance += abi.decode(result, (uint256));
            }
        }
        uint24 activeId = ILBT(yieldToken).getActiveId();

        uint256 amountY = 0;
        uint256 amountX = 0;
        for (uint256 i = 0; i < depositIds.length; i++) {
            uint256 balance = ILBT(yieldToken).balanceOf(
                address(this),
                depositIds[i]
            );
            (uint128 reserveX, uint128 reserveY) = ILBT(yieldToken).getBin(
                depositIds[i]
            );
            uint256 totalSupply = ILBT(yieldToken).totalSupply(depositIds[i]);

            if (depositIds[i] <= activeId) {
                amountY += (balance * uint256(reserveY)) / totalSupply;
            }

            if (depositIds[i] >= activeId) {
                amountX += (balance * uint256(reserveX)) / totalSupply;
            }
        }

        emit LogUint("amountY", amountY);
        emit LogUint("amountX", amountX);
        emit LogUint("balance", IERC20(_asset).balanceOf(address(this)));
        emit LogUint(
            "balance tokenY",
            IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7).balanceOf(
                address(this)
            )
        );
        emit LogUint("totalAssets", totalAssets());
        uint256 postTotalAssets = totalAssets() - outstandingAllowance;

        return ([preTotalAssets, postTotalAssets, 0, 0, 0, 0]);
    }

    function execute(bytes memory data) external override onlyKeeperOrOwner {
        uint256[6] memory stats = _execute(data);

        // Total assets should stay the same or increase (with slippage)
        if (
            stats[1] <
            stats[0].mulDiv(10_000 - slippage, 10_000, Math.Rounding.Ceil)
        ) revert("Total assets decreased");
    }
}
