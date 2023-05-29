// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IMorphoCompound {
    function supply(address _poolToken, uint256 _amount) external;

    function withdraw(address _poolToken, uint256 _amount) external;

    function claimRewards(
        address[] calldata _cTokenAddresses,
        bool _tradeForMorphoToken
    ) external returns (uint256 amountOfRewards);

    function positionsManager() external view returns (address);

    function comptroller() external view returns (address);
}
