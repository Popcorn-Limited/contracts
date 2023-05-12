// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IGauge {
    function lp_token() external view returns (address);

    function balanceOf(address _user) external view returns (uint256);

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _rawAmount) external;

    function reward_count() external view returns (uint256);

    function reward_tokens(uint256 _index) external view returns (address);
}

interface IGaugeFactory {
    function mint(address _gauge) external;

    function get_gauge_from_lp_token(
        address _lpToken
    ) external view returns (address);
}

interface IGaugeController {
    function gauges(uint256 _gaugeId) external view returns (address);
}

interface IMinter {
    function mint(address _gauge) external;

    function token() external view returns (address);

    function controller() external view returns (address);
}

interface IMetaRegistry {
    function pool_list(uint index) external view returns (address);
    function get_lp_token(address pool) external view returns (address);
    function get_n_coins(address pool) external view returns (uint);
    function get_coins(address pool) external view returns (address[8] memory);
}

interface IPool {
    function calc_withdraw_one_coin(uint amount, int128 tokenIndex) external view returns (uint);
    function coins(uint index) external view returns (address);
    function remove_liquidity_one_coin(uint amount, int128 tokenIndex, uint minOut) external;
    function add_liquidity(uint[2] memory amounts, uint minOut) external;
    function add_liquidity(uint[3] memory amounts, uint minOut) external;
    function add_liquidity(uint[4] memory amounts, uint minOut) external;
    function add_liquidity(uint[5] memory amounts, uint minOut) external;
    function add_liquidity(uint[6] memory amounts, uint minOut) external;
    function add_liquidity(uint[7] memory amounts, uint minOut) external;
    function add_liquidity(uint[8] memory amounts, uint minOut) external;
}