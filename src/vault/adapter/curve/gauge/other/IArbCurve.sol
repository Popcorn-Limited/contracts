// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface ICurveLp {
    function calc_withdraw_one_coin(
        uint256 burn_amount,
        int128 i
    ) external view returns (uint256);

    function calc_token_amount(
        uint256[] calldata amounts,
        bool isDeposit
    ) external view returns (uint256);

    function add_liquidity(uint256[] calldata amounts, uint256 minOut) external;

    function remove_liquidity_one_coin(
        uint256 burnAmount,
        int128 indexOut,
        uint256 minOut
    ) external;

    function N_COINS() external view returns (uint256);

    function get_virtual_price() external view returns (uint256);
}

interface IGauge {
    function deposit(uint256 amount) external;

    function withdraw(uint256 burnAmount) external;

    function claim_rewards() external;

    function claimable_reward(
        address user,
        address rewardToken
    ) external view returns (uint256);
}

interface ICurveRouter {
    function exchange(
        address[11] calldata _route,
        uint256[5][5] calldata _swap_params,
        uint256 _amount,
        uint256 _expected,
        address[5] calldata _pools
    ) external returns (uint256);
}

struct CurveSwap {
    address[11] route;
    uint256[5][5] swapParams;
    address[5] pools;
}
