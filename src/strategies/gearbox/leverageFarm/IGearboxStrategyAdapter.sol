// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

/// @title Aave V2 LendingPool adapter interface
interface IAaveV2_LendingPoolAdapter {
    function deposit(address asset, uint256 amount, address, uint16)
        external
        returns (uint256 tokensToEnable, uint256 tokensToDisable);

    function withdraw(address asset, uint256 amount, address)
        external
        returns (uint256 tokensToEnable, uint256 tokensToDisable);
}

interface IAsset {
// solhint-disable-previous-line no-empty-blocks
}

interface IBalancerV2VaultAdapter {
    function joinPoolSingleAsset(bytes32 poolId, IAsset assetIn, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 tokensToEnable, uint256 tokensToDisable);

    function exitPoolSingleAsset(bytes32 poolId, IAsset assetOut, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 tokensToEnable, uint256 tokensToDisable);
}

interface ICompoundV2_CTokenAdapter {
    function mint(uint256 amount) external returns (uint256 tokensToEnable, uint256 tokensToDisable);
    function redeem(uint256 amount) external returns (uint256 tokensToEnable, uint256 tokensToDisable);
}

interface IConvexV1BaseRewardPoolAdapter {
    function stake(uint256) external returns (uint256 tokensToEnable, uint256 tokensToDisable);
    function getReward() external returns (uint256 tokensToEnable, uint256 tokensToDisable);
    function withdraw(uint256, bool claim) external returns (uint256 tokensToEnable, uint256 tokensToDisable);
}

interface IConvexV1BoosterAdapter {
    function deposit(uint256 _pid, uint256, bool _stake)
        external
        returns (uint256 tokensToEnable, uint256 tokensToDisable);

    function withdraw(uint256 _pid, uint256) external returns (uint256 tokensToEnable, uint256 tokensToDisable);
}

interface ILidoV1Adapter {
    function submit(uint256 amount) external returns (uint256 tokensToEnable, uint256 tokensToDisable);
}

interface IwstETHV1Adapter {
    function wrap(uint256 amount) external returns (uint256 tokensToEnable, uint256 tokensToDisable);
    function unwrap(uint256 amount) external returns (uint256 tokensToEnable, uint256 tokensToDisable);
}
