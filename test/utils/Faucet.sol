// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

interface Uniswap {
  function swapExactETHForTokens(
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external payable returns (uint256[] memory amounts);

  function WETH() external pure returns (address);
}

interface CrvSethPool {
  function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external payable;
}

interface Crv3CryptoPool {
  function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amount) external;
}

interface CrvAavePool {
  function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amount, bool use_underlying) external;
}

interface CrvCompPool {
  function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external;
}

interface CrvCvxCrvPool {
  function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external;
}

interface CrvIbBtcPool {
  function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external;
}

interface CrvSBtcPool {
  function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amount) external;
}

interface TriPool {
  function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amounts) external;
}

interface IWETH is IERC20 {
  function deposit() external payable;

  function withdraw(uint256 wad) external;
}

interface CDai is IERC20 {
  function mint(uint256 mintAmount) external returns (uint256);
}

contract Faucet {
  using SafeERC20 for IERC20;
  using SafeERC20 for CDai;

  Uniswap public uniswap;

  address public triPool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
  address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  IERC20 public threeCrv = IERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);

  address public usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
  Crv3CryptoPool public crv3CryptoPool = Crv3CryptoPool(0xD51a44d3FaE010294C616388b506AcdA1bfAAE46);
  IERC20 public crv3CryptoLP = IERC20(0xc4AD29ba4B3c580e6D59105FFf484999997675Ff);

  CrvAavePool public crvAavePool = CrvAavePool(0xDeBF20617708857ebe4F679508E7b7863a8A8EeE);
  IERC20 public crvAaveLP = IERC20(0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900);

  CDai public cDai = CDai(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
  CrvCompPool public crvCompPool = CrvCompPool(0xA2B47E3D5c44877cca798226B7B8118F9BFb7A56);
  IERC20 public crvCompLP = IERC20(0x845838DF265Dcd2c412A1Dc9e959c7d08537f8a2);

  address public crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
  CrvCvxCrvPool public crvCvxCrvPool = CrvCvxCrvPool(0x9D0464996170c6B9e75eED71c68B99dDEDf279e8);
  IERC20 public crvCvxCrvLP = IERC20(0x9D0464996170c6B9e75eED71c68B99dDEDf279e8);

  address public wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
  CrvSBtcPool public crvSBtcPool = CrvSBtcPool(0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714);
  CrvIbBtcPool public crvIbBtcPool = CrvIbBtcPool(0xFbdCA68601f835b27790D98bbb8eC7f05FDEaA9B);
  IERC20 public crvSBtcLP = IERC20(0x075b1bb99792c9E1041bA13afEf80C91a1e70fB3);
  IERC20 public crvIbBtcLP = IERC20(0xFbdCA68601f835b27790D98bbb8eC7f05FDEaA9B);

  IWETH public weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
  CrvSethPool public crvSethPool = CrvSethPool(0xc5424B857f758E906013F3555Dad202e4bdB4567);
  IERC20 public crvSethLP = IERC20(0xA3D87FffcE63B53E0d54fAa1cc983B7eB0b74A9c);

  constructor(address uniswap_) {
    uniswap = Uniswap(uniswap_);
    IERC20(dai).safeApprove(address(cDai), type(uint256).max);
    cDai.safeApprove(address(crvCompPool), type(uint256).max);
    IERC20(crv).safeApprove(address(crvCvxCrvPool), type(uint256).max);
    IERC20(dai).safeApprove(address(crvAavePool), type(uint256).max);
    IERC20(dai).safeApprove(address(triPool), type(uint256).max);
    IERC20(usdt).safeApprove(address(crv3CryptoPool), type(uint256).max);
    IERC20(wbtc).safeApprove(address(crvSBtcPool), type(uint256).max);
    IERC20(crvSBtcLP).safeApprove(address(crvIbBtcPool), type(uint256).max);
  }

  function sendTokens(address token, uint256 amount, address recipient) public returns (uint256[] memory) {
    address[] memory path = new address[](2);
    path[0] = uniswap.WETH();
    path[1] = token;
    return uniswap.swapExactETHForTokens{ value: amount * 1 ether }(0, path, recipient, block.timestamp);
  }

  function sendCrv3CryptoLPTokens(uint256 amount, address recipient) public {
    uint256 usdtAmount = sendTokens(usdt, amount, address(this))[1];
    crv3CryptoPool.add_liquidity([usdtAmount, 0, 0], 0);
    crv3CryptoLP.transfer(recipient, crv3CryptoLP.balanceOf(address(this)));
  }

  function sendCrvAaveLPTokens(uint256 amount, address recipient) public {
    uint256 daiAmount = sendTokens(dai, amount, address(this))[1];
    crvAavePool.add_liquidity([daiAmount, 0, 0], 0, true);
    crvAaveLP.transfer(recipient, crvAaveLP.balanceOf(address(this)));
  }

  function sendCrvCompLPTokens(uint256 amount, address recipient) public {
    uint256 daiAmount = sendTokens(dai, amount, address(this))[1];
    cDai.mint(daiAmount);
    uint256 cDaiAmount = cDai.balanceOf(address(this));
    crvCompPool.add_liquidity([cDaiAmount, 0], 0);
    crvCompLP.transfer(recipient, crvCompLP.balanceOf(address(this)));
  }

  function sendCrvCvxCrvLPTokens(uint256 amount, address recipient) public {
    uint256 crvAmount = sendTokens(crv, amount, address(this))[1];
    crvCvxCrvPool.add_liquidity([crvAmount, 0], 0);
    crvCvxCrvLP.transfer(recipient, crvCvxCrvLP.balanceOf(address(this)));
  }

  function sendCrvIbBtcLPTokens(uint256 amount, address recipient) public {
    uint256 wbtcAmount = sendTokens(wbtc, amount, address(this))[1];
    crvSBtcPool.add_liquidity([0, wbtcAmount, 0], 0);
    crvIbBtcPool.add_liquidity([0, crvSBtcLP.balanceOf(address(this))], 0);
    crvIbBtcLP.transfer(recipient, crvIbBtcLP.balanceOf(address(this)));
  }

  function sendCrvSethLPTokens(uint256 amount, address recipient) public payable {
    crvSethPool.add_liquidity{ value: amount * 1 ether }([amount * 1 ether, 0], 0);
    crvSethLP.transfer(recipient, crvSethLP.balanceOf(address(this)));
  }

  function sendThreeCrv(uint256 amount, address recipient) public {
    uint256 daiAmount = sendTokens(dai, amount, address(this))[1];
    TriPool(triPool).add_liquidity([daiAmount, 0, 0], 0);
    threeCrv.transfer(recipient, threeCrv.balanceOf(address(this)));
  }
}
