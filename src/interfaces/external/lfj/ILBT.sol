// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.0
pragma solidity ^0.8.25;

interface ILBT {
    /**
     * @notice Returns the amount of tokens of type `id` owned by `account`.
     * @param account The address of the owner.
     * @param id The token id.
     * @return The amount of tokens of type `id` owned by `account`.
     */
    function balanceOf(
        address account,
        uint256 id
    ) external view returns (uint256);

    /**
     * @notice Returns the total supply of token of type `id`.
     * /**
     * @dev This is the amount of token of type `id` minted minus the amount burned.
     * @param id The token id.
     * @return The total supply of that token id.
     */
    function totalSupply(uint256 id) external view returns (uint256);

    /**
     * @notice Return the balance of multiple (account/id) pairs.
     * @param accounts The addresses of the owners.
     * @param ids The token ids.
     * @return batchBalances The balance for each (account, id) pair.
     */
    function balanceOfBatch(
        address[] calldata accounts,
        uint256[] calldata ids
    ) external view returns (uint256[] memory batchBalances);

    /**
     * @notice Returns the reserves of a bin
     * @param id The id of the bin
     * @return binReserveX The reserve of token X in the bin
     * @return binReserveY The reserve of token Y in the bin
     */
    function getBin(uint256 id) external view returns (uint128, uint128);

    /**
     * @notice Returns the active id of the Liquidity Book Pair
     * @dev The active id is the id of the bin that is currently being used for swaps.
     * The price of the active bin is the price of the Liquidity Book Pair and can be calculated as follows:
     * `price = (1 + binStep / 10_000) ^ (activeId - 2^23)`
     * @return activeId The active id of the Liquidity Book Pair
     */
    function getActiveId() external view returns (uint24);

    /**
     * @notice Returns the token X of the Liquidity Book Pair
     * @return tokenX The address of the token X
     */
    function getTokenX() external view returns (address);

    /**
     * @notice Returns the token Y of the Liquidity Book Pair
     * @return tokenY The address of the token Y
     */
    function getTokenY() external view returns (address);
}
