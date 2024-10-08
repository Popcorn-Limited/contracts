// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

import {Errors, BaseAdapter, IPriceOracle} from "./BaseAdapter.sol";
import {ScaleUtils} from "src/lib/euler/ScaleUtils.sol";
import {Owned} from "src/utils/Owned.sol";

struct OracleStep {
    address base;
    address quote;
    address oracle;
}

/// @title CrossAdapter
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice PriceOracle that chains two PriceOracles.
/// @dev For example, CrossAdapter can price wstETH/USD by querying a wstETH/stETH oracle and a stETH/USD oracle.
contract CrossOracle is BaseAdapter, Owned {
    string public constant name = "CrossAdapter";

    mapping(address => mapping(address => OracleStep[])) public oraclePath;
    mapping(address => mapping(address => OracleStep[])) public proposedOraclePath;
    mapping(address => mapping(address => uint256)) public proposedTime;

    event OracleAdded(address base, address quote);
    event OracleProposed(address base, address quote);
    event OracleChanged(address base, address quote);

    error OracleExists();
    error NoOraclePath();
    error RespectTimeLock();

    /// @notice Deploy a CrossAdapter.
    /// @param _owner Owner of the contract
    constructor(address _owner) Owned(_owner) {}

    /// @notice Get a quote by chaining the cross oracles.
    /// @dev For the inverse direction it calculates quote/cross * cross/base.
    /// For the forward direction it calculates base/cross * cross/quote.
    /// @param inAmount The amount of `base` to convert.
    /// @param base The token that is being priced.
    /// @param quote The token that is the unit of account.
    /// @return The converted amount by chaining the cross oracles.
    function _getQuote(uint256 inAmount, address base, address quote) internal view override returns (uint256) {
        OracleStep[] memory oracleSteps = oraclePath[base][quote];

        uint256 len = oracleSteps.length;
        if (len == 0) revert Errors.PriceOracle_NotSupported(base, quote);

        for (uint256 i; i < len; i++) {
            inAmount = IPriceOracle(oracleSteps[i].oracle).getQuote(inAmount, oracleSteps[i].base, oracleSteps[i].quote);
        }

        return inAmount;
    }

    function addOraclePath(address base, address quote, OracleStep[] memory oracleSteps) external onlyOwner {
        if (oraclePath[base][quote].length > 0) revert OracleExists();

        uint256 len = oracleSteps.length;
        if (len == 0) revert NoOraclePath();

        for (uint256 i; i < len; i++) {
            oraclePath[base][quote].push(oracleSteps[i]);
        }

        emit OracleAdded(base, quote);
    }

    function proposeOraclePath(address base, address quote, OracleStep[] memory oracleSteps) external onlyOwner {
        delete proposedOraclePath[base][quote];

        uint256 len = oracleSteps.length;
        if (len > 0) {
            for (uint256 i; i < len; i++) {
                proposedOraclePath[base][quote].push(oracleSteps[i]);
            }
        }

        proposedTime[base][quote] = block.timestamp + 3 days;

        emit OracleProposed(base, quote);
    }

    function changeOraclePath(address base, address quote) external onlyOwner {
        if (block.timestamp < proposedTime[base][quote]) {
            revert RespectTimeLock();
        }

        delete oraclePath[base][quote];

        uint256 len = proposedOraclePath[base][quote].length;
        if (len > 0) {
            for (uint256 i; i < len; i++) {
                oraclePath[base][quote].push(proposedOraclePath[base][quote][i]);
            }
        }

        delete proposedOraclePath[base][quote];
        delete proposedTime[base][quote];

        emit OracleChanged(base, quote);
    }
}
