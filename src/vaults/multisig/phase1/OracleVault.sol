// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {AsyncVault, InitializeParams} from "./AsyncVault.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";

struct ChangeProposal {
    address addr;
    uint256 timestamp;
}

/**
 * @title   OracleVault
 * @author  RedVeil
 * @notice  ERC-7540 (https://eips.ethereum.org/EIPS/eip-7540) compliant async redeem vault using a PushOracle for pricing and a Safe for managing assets
 * @dev     Oracle and safe security is handled in other contracts. We simply assume they are secure and don't implement any further checks in this contract
 */
contract OracleVault is AsyncVault {
    address public safe;

    /**
     * @notice Constructor for the OracleVault
     * @param params The parameters to initialize the vault with
     * @param oracle_ The oracle to use for pricing
     * @param safe_ The safe which will manage the assets
     */
    constructor(
        InitializeParams memory params,
        address oracle_,
        address safe_
    ) AsyncVault(params) {
        if (safe_ == address(0) || oracle_ == address(0))
            revert Misconfigured();

        safe = safe_;
        oracle = IPriceOracle(oracle_);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    IPriceOracle public oracle;

    /// @notice Total amount of underlying `asset` token managed by the safe.
    function totalAssets() public view override returns (uint256) {
        return oracle.getQuote(totalSupply, share, address(asset));
    }

    /*//////////////////////////////////////////////////////////////
                            ERC-4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal function to handle the deposit and mint
    function afterDeposit(uint256 assets, uint256) internal override {
        // Deposit and mint already have the `whenNotPaused` modifier so we don't need to check it here
        _takeFees();

        // Transfer assets to the safe
        SafeTransferLib.safeTransfer(asset, safe, assets);
    }

    /*//////////////////////////////////////////////////////////////
                    BaseControlledAsyncRedeem OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal function to transfer assets from the safe to the vault before fulfilling a redeem
    function beforeFulfillRedeem(uint256 assets, uint256) internal override {
        SafeTransferLib.safeTransferFrom(asset, safe, address(this), assets);
    }

    /*//////////////////////////////////////////////////////////////
                    AsyncVault OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal function to handle the withdrawal incentive
    function handleWithdrawalIncentive(
        uint256 fee,
        address feeRecipient
    ) internal override {
        if (fee > 0)
            // Transfer the fee from the safe to the fee recipient
            SafeTransferLib.safeTransferFrom(asset, safe, feeRecipient, fee);
    }

    /*//////////////////////////////////////////////////////////////
                        SWITCH SAFE LOGIC
    //////////////////////////////////////////////////////////////*/

    ChangeProposal public proposedSafe;

    event SafeProposed(address indexed proposedSafe);
    event SafeChanged(address indexed oldSafe, address indexed newSafe);

    /**
     * @notice Proposes a new safe that can be accepted by the owner after a delay
     * @param newSafe The new safe to propose
     * @dev !!! This is a dangerous operation and should be used with extreme caution !!!
     */
    function proposeSafe(address newSafe) external onlyOwner {
        require(newSafe != address(0), "SafeVault/invalid-safe");

        proposedSafe = ChangeProposal({
            addr: newSafe,
            timestamp: block.timestamp
        });

        emit SafeProposed(newSafe);
    }

    /**
     * @notice Accepts the proposed safe
     * @dev !!! This is a dangerous operation and should be used with extreme caution !!!
     * @dev This will pause the vault to ensure the oracle is set up correctly and no one sends deposits with faulty prices
     * @dev Its important to ensure that the oracle will be switched before unpausing the vault again
     */
    function acceptSafe() external onlyOwner {
        ChangeProposal memory proposal = proposedSafe;

        require(proposal.addr != address(0), "SafeVault/no-safe-proposed");
        require(
            proposal.timestamp + 3 days <= block.timestamp,
            "SafeVault/safe-not-yet-acceptable"
        );

        emit SafeChanged(safe, proposal.addr);

        safe = proposal.addr;

        delete proposedSafe;

        // Pause to ensure that no deposits get through with faulty prices
        _pause();
    }

    /*//////////////////////////////////////////////////////////////
                        SWITCH ORACLE LOGIC
    //////////////////////////////////////////////////////////////*/

    ChangeProposal public proposedOracle;

    event OracleProposed(address indexed proposedOracle);
    event OracleChanged(address indexed oldOracle, address indexed newOracle);

    /**
     * @notice Proposes a new oracle that can be accepted by the owner after a delay
     * @param newOracle The new oracle to propose
     * @dev !!! This is a dangerous operation and should be used with extreme caution !!!
     */
    function proposeOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "SafeVault/invalid-oracle");

        proposedOracle = ChangeProposal({
            addr: newOracle,
            timestamp: block.timestamp
        });

        emit OracleProposed(newOracle);
    }

    /**
     * @notice Accepts the proposed oracle
     * @dev !!! This is a dangerous operation and should be used with extreme caution !!!
     * @dev This will pause the vault to ensure the oracle is set up correctly and no one sends deposits with faulty prices
     * @dev Its important to ensure that the oracle will be switched before unpausing the vault again
     */
    function acceptOracle() external onlyOwner {
        ChangeProposal memory proposal = proposedOracle;

        require(proposal.addr != address(0), "SafeVault/no-oracle-proposed");
        require(
            proposal.timestamp + 3 days <= block.timestamp,
            "SafeVault/oracle-not-yet-acceptable"
        );

        emit OracleChanged(address(oracle), proposal.addr);

        oracle = IPriceOracle(proposal.addr);

        delete proposedOracle;

        // Pause to ensure that no deposits get through with faulty prices
        _pause();
    }
}
