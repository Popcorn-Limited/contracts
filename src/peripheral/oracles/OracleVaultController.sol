// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Owned} from "src/utils/Owned.sol";
import {Pausable} from "src/utils/Pausable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC4626} from "solmate/tokens/ERC4626.sol";
import {IPushOracle} from "src/interfaces/IPushOracle.sol";

/// @notice Price update struct
struct PriceUpdate {
    /// @notice The vault to update the price for
    address vault;
    /// @notice The asset to update the price for (the asset the vault is denominated in)
    address asset;
    /// @notice The share value in assets
    uint256 shareValueInAssets;
    /// @notice The asset value in shares
    uint256 assetValueInShares;
}

/// @notice Safety limits for price updates
struct Limit {
    /// @notice Maximum allowed price jump from one update to the next (1e18 = 100%)
    uint256 jump; // 1e18 = 100%
    /// @notice Maximum allowed drawdown from the HWM (1e18 = 100%)
    uint256 drawdown; // 1e18 = 100%
}

/**
 * @title   OracleVaultController
 * @author  RedVeil
 * @notice  Controller for updating the price of vaults using a PushOracle
 * @dev     Updates are made by permissioned keepers in regular intervals.
 * @dev     A large jump in price or drawdown will pause the vault to safeguard against faulty updates or exploits
 */
contract OracleVaultController is Owned {
    using FixedPointMathLib for uint256;

    IPushOracle public oracle;

    event KeeperUpdated(address previous, address current);

    error NotKeeperNorOwner();

    constructor(address _oracle, address _owner) Owned(_owner) {
        oracle = IPushOracle(_oracle);
    }

    /*//////////////////////////////////////////////////////////////
                            ORACLE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev vault => HWM
    mapping(address => uint256) public highWaterMarks;

    event VaultAdded(address vault);

    /**
     * @notice Update the price and hwm of a vault. A large jump in price or drawdown will pause the vault if it is not already paused
     * @param priceUpdate The price update to update
     * @dev Vault prices shouldnt fluctuate too much since the oracle should be updated regularly. If they do this could be a error, exploit attempt or simply a price jump
     * in these cases we will still update the price (future updates will revert the change if it was a faulty update) BUT pause the vault for additionals deposits
     */
    function updatePrice(PriceUpdate calldata priceUpdate) external {
        _updatePrice(priceUpdate);
    }

    /**
     * @notice Update the prices of multiple vaults
     * @param priceUpdates The price updates to update
     */
    function updatePrices(PriceUpdate[] calldata priceUpdates) external {
        for (uint256 i; i < priceUpdates.length; i++) {
            _updatePrice(priceUpdates[i]);
        }
    }

    /// @notice Internal function to update the price of a vault
    function _updatePrice(
        PriceUpdate calldata priceUpdate
    ) internal onlyKeeperOrOwner(priceUpdate.vault) {
        // Caching
        uint256 lastPrice = oracle.prices(priceUpdate.vault, priceUpdate.asset);
        uint256 hwm = highWaterMarks[priceUpdate.vault];
        bool paused = Pausable(priceUpdate.vault).paused();
        Limit memory limit = limits[priceUpdate.vault];

        // Check for price jump or drawdown
        if (
            // Check for price jump down
            priceUpdate.shareValueInAssets <
            lastPrice.mulDivDown(1e18 - limit.jump, 1e18) ||
            // Check for price jump up
            priceUpdate.shareValueInAssets >
            lastPrice.mulDivDown(1e18 + limit.jump, 1e18) ||
            // Check for drawdown
            priceUpdate.shareValueInAssets <
            hwm.mulDivDown(1e18 - limit.drawdown, 1e18)
        ) {
            // Pause the vault if it is not already paused
            if (!Pausable(priceUpdate.vault).paused()) {
                Pausable(priceUpdate.vault).pause();
            }
        } else if (priceUpdate.shareValueInAssets > hwm) {
            // Update HWM if there wasnt a jump or drawdown
            highWaterMarks[priceUpdate.vault] = priceUpdate.shareValueInAssets;
        }

        // Update the price
        oracle.setPrice(
            priceUpdate.vault,
            priceUpdate.asset,
            priceUpdate.shareValueInAssets,
            priceUpdate.assetValueInShares
        );
    }

    /**
     * @notice Add a vault to the controller to be able to update its price
     * @param vault The vault to add
     * @dev Will always initialize the price to 1e18 (1:1) -- This is to prevent pausing the vault on the first update
     * @dev This function should be called before the vault has received any deposits
     */
    function addVault(address vault) external onlyOwner {
        highWaterMarks[vault] = 1e18;

        oracle.setPrice(vault, address(ERC4626(vault).asset()), 1e18, 1e18);

        emit VaultAdded(vault);
    }

    /*//////////////////////////////////////////////////////////////
                        KEEPER LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev vault => keeper
    mapping(address => address) public keepers;

    event KeeperUpdated(address vault, address previous, address current);

    /**
     * @notice Set the keeper for a vault
     * @param _vault The vault to set the keeper for
     * @param _keeper The keeper to set for the vault
     */
    function setKeeper(address _vault, address _keeper) external onlyOwner {
        emit KeeperUpdated(_vault, keepers[_vault], _keeper);

        keepers[_vault] = _keeper;
    }

    /**
     * @notice Modifier to check if the sender is the owner or the keeper for a vault
     * @param _vault The vault to check the keeper for
     */
    modifier onlyKeeperOrOwner(address _vault) {
        if (msg.sender != owner && msg.sender != keepers[_vault])
            revert NotKeeperNorOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev vault => Limit
    mapping(address => Limit) public limits;

    event LimitUpdated(address vault, Limit previous, Limit current);

    /**
     * @notice Set the limit for a vault
     * @param _vault The vault to set the limit for
     * @param _limit The limit to set for the vault
     */
    function setLimit(address _vault, Limit memory _limit) external onlyOwner {
        _setLimit(_vault, _limit);
    }

    /**
     * @notice Set the limits for multiple vaults
     * @param _vaults The vaults to set the limits for
     * @param _limits The limits to set for the vaults
     */
    function setLimits(
        address[] memory _vaults,
        Limit[] memory _limits
    ) external onlyOwner {
        if (_vaults.length != _limits.length) revert("Invalid length");

        for (uint256 i; i < _vaults.length; i++) {
            _setLimit(_vaults[i], _limits[i]);
        }
    }

    /// @notice Internal function to set the limit for a vault
    function _setLimit(address _vault, Limit memory _limit) internal {
        if (_limit.jump > 1e18 || _limit.drawdown > 1e18)
            revert("Invalid limit");
        emit LimitUpdated(_vault, limits[_vault], _limit);

        limits[_vault] = _limit;
    }

    /*//////////////////////////////////////////////////////////////
                        OTHER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Accept the ownership of the oracle
     * @dev Used after construction since we otherwise have recursive dependencies on the construction of this contract and the oracle
     */
    function acceptOracleOwnership() external onlyOwner {
        Owned(address(oracle)).acceptOwnership();
    }
}
