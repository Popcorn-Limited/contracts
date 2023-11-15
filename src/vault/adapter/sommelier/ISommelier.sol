pragma solidity ^0.8.15;

interface IVault {
    function asset() external view returns (address);

    function balanceOf(address) external view returns (uint256);

    function shareLockPeriod() external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function convertToShares(uint256 amount) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external;

    function redeem(uint256 shares, address receiver, address owner) external;

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
}
