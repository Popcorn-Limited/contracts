// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";

import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IWETH} from "../../../interfaces/external/IWETH.sol";
import {ICurveMetapool} from "../../../interfaces/external/curve/ICurveMetapool.sol";
import {ILido, VaultAPI} from "./ILido.sol";
import {SafeMath} from "openzeppelin-contracts/utils/math/SafeMath.sol";

/// @title LidoAdapter
/// @author zefram.eth
/// @notice ERC4626 wrapper for Lido stETH
/// @dev Uses stETH's internal shares accounting instead of using regular vault accounting
/// since this prevents attackers from atomically increasing the vault's share value
/// and exploiting lending protocols that use this vault as a borrow asset.
contract LidoAdapter is AdapterBase {
    // using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;
    ICurveMetapool public constant StableSwapSTETH =
        ICurveMetapool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    uint256 public slippage; // 1e18 = 100% slippage, 1e14 = 1 BPS slippage

    /// @notice The poolId inside Convex booster for relevant Curve lpToken.
    uint256 public pid;

    /// @notice The booster address for Convex
    ILido public lido;

    // address public immutable weth;
    IWETH public weth;

    /*//////////////////////////////////////////////////////////////
                                INITIALIZATION
  //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize a new Lido Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param lidoInitData Encoded data for the Lido adapter initialization.
     * @dev `_slippage` - allowed slippage in 1e18
     * @dev `_pid` - The poolId for lpToken.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address _lidoAddress,
        bytes memory lidoInitData
    ) public initializer {
        __AdapterBase_init(adapterInitData);

        (uint256 _slippage, uint256 _pid) = abi.decode(
            lidoInitData,
            (uint256, uint256)
        );

        lido = ILido(ILido(_lidoAddress).token());
        pid = _pid;
        weth = IWETH(ILido(_lidoAddress).weth());
        slippage = _slippage;

        _name = string.concat(
            "VaultCraft Lido ",
            IERC20Metadata(address(weth)).name(),
            " Adapter"
        );
        _symbol = string.concat(
            "vcLdo-",
            IERC20Metadata(address(weth)).symbol()
        );

        IERC20(address(lido)).approve(
            address(StableSwapSTETH),
            type(uint256).max
        );
        IERC20(address(weth)).approve(
            address(StableSwapSTETH),
            type(uint256).max
        );
        IERC20(address(weth)).approve(address(lido), type(uint256).max);
    }

    //we get eth
    receive() external payable {}

    function name()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _name;
    }

    function symbol()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function _underlyingBalance() internal view returns (uint256) {
        return lido.sharesOf(address(this));
    }

    function _totalAssets() internal view override returns (uint256) {
        return lido.balanceOf(address(this)); // this can be higher than the total assets deposited due to staking rewards
    }

    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256) {
        return
            _convertToShares(
                assets + assets.mulDiv(slippage, 1e18, Math.Rounding.Up),
                Math.Rounding.Up
            );
    }

    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256) {
        uint256 assets = _convertToAssets(shares, Math.Rounding.Down);
        return assets + assets.mulDiv(slippage, 1e18, Math.Rounding.Up);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into LIDO pool
    function _protocolDeposit(
        uint256 assets,
        uint256
    ) internal override {
        weth.withdraw(assets); // Grab native Eth from Weth contract
        lido.submit{value: assets}(FEE_RECIPIENT); // Submit to Lido Contract
    }

    /// @notice Withdraw from LIDO pool
    function _protocolWithdraw(
        uint256 assets,
        uint256
    ) internal override {
        uint256 amountRecieved = StableSwapSTETH.exchange(
            STETHID,
            WETHID,
            assets,
            0
        );
        weth.deposit{value: amountRecieved}(); // get wrapped eth back
    }
}
