// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IAlpacaLendV2Vault {
    function token() external view returns (address);

    function balanceOf(address _user) external view returns (uint256);

    function totalToken() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _shares) external;
}

interface IAlpacaLendV2Manger {
    function deposit(address _token, uint256 _amount) external;

    function withdraw(address _ibToken, uint256 _amount) external;

    function miniFL() external view returns (address);
}

interface IAlpacaLendV2MiniFL {
    function stakingTokens(uint256 _pid) external view returns (address);
}

interface IAlpacaLendV2IbToken {
    function convertToAssets(uint256 _amount) external view returns (uint256);

    function convertToShares(uint256 _amount) external view returns (uint256);

    function balanceOf(address _user) external view returns (uint256);

    function asset() external view returns (address);

    function withdraw(
        uint256 _assets,
        address _receiver,
        address _owner
    ) external;
}
