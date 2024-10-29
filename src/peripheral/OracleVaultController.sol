// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Owned} from "src/utils/Owned.sol";
import {Pausable} from "src/utils/Pausable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC4626} from "solmate/tokens/ERC4626.sol";

interface IPushOracle {
    function setPrice(
        address base,
        address quote,
        uint256 bqPrice,
        uint256 qbPrice
    ) external;

    function setPrices(
        address[] memory bases,
        address[] memory quotes,
        uint256[] memory bqPrices,
        uint256[] memory qbPrices
    ) external;

    function prices(
        address base,
        address quote
    ) external view returns (uint256);
}

struct Limit {
    uint256 jump; // 1e18 = 100%
    uint256 drawdown; // 1e18 = 100%
}

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

    struct PriceUpdate {
        address vault;
        address asset;
        uint256 shareValueInAssets;
        uint256 assetValueInShares;
    }

    mapping(address => uint256) public highWaterMarks;

    event VaultAdded(address vault);

    function updatePrice(PriceUpdate calldata priceUpdate) external {
        _updatePrice(priceUpdate);
    }

    function updatePrices(PriceUpdate[] calldata priceUpdates) external {
        for (uint256 i; i < priceUpdates.length; i++) {
            _updatePrice(priceUpdates[i]);
        }
    }

    function _updatePrice(
        PriceUpdate calldata priceUpdate
    ) internal onlyKeeperOrOwner(priceUpdate.vault) {
        uint256 lastPrice = oracle.prices(priceUpdate.vault, priceUpdate.asset);
        uint256 hwm = highWaterMarks[priceUpdate.vault];
        Limit memory limit = limits[priceUpdate.vault];
        bool paused = Pausable(priceUpdate.vault).paused();

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
            if (!Pausable(priceUpdate.vault).paused()) {
                Pausable(priceUpdate.vault).pause();
            }
        } else if (priceUpdate.shareValueInAssets > hwm) {
            // Update HWM if there wasnt a jump or drawdown
            highWaterMarks[priceUpdate.vault] = priceUpdate.shareValueInAssets;
        }

        oracle.setPrice(
            priceUpdate.vault,
            priceUpdate.asset,
            priceUpdate.shareValueInAssets,
            priceUpdate.assetValueInShares
        );
    }

    function addVault(address vault) external onlyOwner {
        highWaterMarks[vault] = 1e18;

        oracle.setPrice(
            vault,
            address(ERC4626(vault).asset()),
            1e18,
            1e18
        );

        emit VaultAdded(vault);
    }

    /*//////////////////////////////////////////////////////////////
                        KEEPER LOGIC
    //////////////////////////////////////////////////////////////*/

    mapping(address => address) public keepers;

    event KeeperUpdated(address vault, address previous, address current);

    function setKeeper(address _vault, address _keeper) external onlyOwner {
        emit KeeperUpdated(_vault, keepers[_vault], _keeper);

        keepers[_vault] = _keeper;
    }

    modifier onlyKeeperOrOwner(address _vault) {
        if (msg.sender != owner && msg.sender != keepers[_vault])
            revert NotKeeperNorOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    mapping(address => Limit) public limits;

    event LimitUpdated(address vault, Limit previous, Limit current);

    function setLimit(address _vault, Limit memory _limit) external onlyOwner {
        _setLimit(_vault, _limit);
    }

    function setLimits(
        address[] memory _vaults,
        Limit[] memory _limits
    ) external onlyOwner {
        if (_vaults.length != _limits.length) revert("Invalid length");

        for (uint256 i; i < _vaults.length; i++) {
            _setLimit(_vaults[i], _limits[i]);
        }
    }

    function _setLimit(address _vault, Limit memory _limit) internal {
        if (_limit.jump > 1e18 || _limit.drawdown > 1e18)
            revert("Invalid limit");
        emit LimitUpdated(_vault, limits[_vault], _limit);

        limits[_vault] = _limit;
    }

    /*//////////////////////////////////////////////////////////////
                        OTHER LOGIC
    //////////////////////////////////////////////////////////////*/

    function acceptOracleOwnership() external onlyOwner {
        Owned(address(oracle)).acceptOwnership();
    }
}
