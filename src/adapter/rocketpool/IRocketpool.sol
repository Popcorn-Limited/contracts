// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IRocketStorage {
    // Getters
    function getAddress(bytes32 _key) external view returns (address);
}

interface IrETH is IERC20 {
    function getEthValue(uint256 _rethAmount) external view returns (uint256);
    function getRethValue(uint256 _ethAmount) external view returns (uint256);
    function getExchangeRate() external view returns (uint256);
    function getTotalCollateral() external view returns (uint256);
    function getCollateralRate() external view returns (uint256);
    function depositExcess() external payable;
    function depositExcessCollateral() external;
    function mint(uint256 _ethAmount, address _to) external;
    function burn(uint256 _rethAmount) external;
}

interface IRocketDepositPool {
    function getBalance() external view returns (uint256);
    function deposit() external payable;
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address) external view returns(uint256);
}

interface ICurveMetapool {
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256);
}

interface IRocketDepositSettings {
    function getDepositFee() external view returns (uint256);
    function getMinimumDeposit() external view returns (uint256);
}

interface IRocketNetworkBalances {
    function getTotalETHBalance() external view returns (uint256);
}
