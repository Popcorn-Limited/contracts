// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IEllipsis {
    function add_liquidity(
        uint256[2] memory amounts,
        uint256 min_mint_amount
    ) external;

    function add_liquidity(
        uint256[3] memory amounts,
        uint256 min_mint_amount
    ) external;

    function add_liquidity(
        uint256[4] memory amounts,
        uint256 min_mint_amount
    ) external;

    function remove_liquidity_one_coin(
        uint256 amount,
        int128 i,
        uint256 min_amount
    ) external;

    function coins(uint256 index) external view returns (address);

    function calc_withdraw_one_coin(
        uint256 amount,
        int128 i
    ) external view returns (uint256);
}

interface ILpStaking {
    // Info of each user.
    struct UserInfo {
        uint256 depositAmount; // The amount of tokens deposited into the contract.
        uint256 adjustedAmount; // The user's effective balance after boosting, used to calculate emission rates.
        uint256 rewardDebt;
        uint256 claimable;
    }

    function registeredTokens(uint256 pId) external view returns (address);

    /**
        @notice Claim pending rewards for one or more tokens for a user.
        @dev Also updates the claimer's boost.
        @param _user Address to claim rewards for. Reverts if the caller is not the
                     claimer and the claimer has blocked third-party actions.
        @param _tokens Array of LP token addresses to claim for.
        @return uint256 Claimed reward amount
    */
    function claim(
        address _user,
        address[] calldata _tokens
    ) external returns (uint256);

    function rewardToken() external view returns (address);

    function userInfo(
        address _token,
        address _user
    ) external view returns (UserInfo memory);

    function deposit(
        address _token,
        uint256 _amount,
        bool _claimRewards
    ) external returns (uint256);

    function withdraw(
        address _token,
        uint256 _amount,
        bool _claimRewards
    ) external returns (uint256);
}

interface IAddressProvider {
    function get_lp_token(address pool) external view returns (address);

    function get_n_coins(address pool) external view returns (uint256);

    function get_coins(address pool) external view returns (address[4] memory);
}
