// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface ICurveMetapool {
    function get_virtual_price() external view returns (uint256);

    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 min_mint_amounts
    ) external returns (uint256);

    function add_liquidity(
        uint256[2] calldata _amounts,
        uint256 _min_mint_amounts,
        address _receiver
    ) external returns (uint256);

    function add_liquidity(
        uint256[3] calldata amounts,
        uint256 min_mint_amounts
    ) external returns (uint256);

    function add_liquidity(
        uint256[3] calldata _amounts,
        uint256 _min_mint_amounts,
        address _receiver
    ) external returns (uint256);

    function add_liquidity(
        uint256[4] calldata amounts,
        uint256 min_mint_amounts
    ) external;

    function add_liquidity(
        uint256[4] calldata _amounts,
        uint256 _min_mint_amounts,
        address _receiver
    ) external returns (uint256);

    function remove_liquidity_one_coin(
        uint256 amount,
        int128 i,
        uint256 min_underlying_amount
    ) external;

    function remove_liquidity_one_coin(
        uint256 amount,
        int128 i,
        uint256 min_underlying_amount,
        bool donate_dust
    ) external;

    function calc_withdraw_one_coin(
        uint256 _token_amount,
        int128 i
    ) external view returns (uint256);

    //Some pools use exchange (sUsd,3crv)...
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256);

    //...And some others use exchange_underlying (mim,3crv)
    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256);

    function lp_price() external view returns (uint256);

    function price_oracle() external view returns (uint256);

    function balances(uint256 i) external view returns (uint256);

    function remove_liquidity(
        uint256 amount,
        uint256[4] memory min_amounts
    ) external;
}
