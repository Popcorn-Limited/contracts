// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

interface IGauge {
    function lp_token() external view returns (address);

    function balanceOf(address _user) external view returns (uint256);

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _rawAmount) external;

    function reward_count() external view returns (uint256);

    function reward_tokens(uint256 _index) external view returns (address);

    function claim_rewards() external;

    function claim_rewards(address user) external;

    function claimable_reward(address user, address rewardToken) external view returns (uint256);
}

interface IGaugeFactory {
    function mint(address _gauge) external;

    function get_gauge_from_lp_token(address _lpToken) external view returns (address);
}

interface IGaugeController {
    function gauges(uint256 _gaugeId) external view returns (address);
}

interface IMinter {
    function mint(address _gauge) external;

    function token() external view returns (address);

    function controller() external view returns (address);
}

interface ICurveLp {
    function calc_withdraw_one_coin(uint256 burn_amount, int128 i) external view returns (uint256);

    function calc_token_amount(uint256[] calldata amounts, bool isDeposit) external view returns (uint256);

    function add_liquidity(uint256[] calldata amounts, uint256 minOut) external;

    function remove_liquidity_one_coin(uint256 burnAmount, int128 indexOut, uint256 minOut) external;

    function N_COINS() external view returns (uint256);

    function coins(uint256 i) external view returns (address);

    function get_virtual_price() external view returns (uint256);
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
