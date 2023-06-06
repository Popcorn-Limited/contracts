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
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    uint256 private WETHID;
    uint256 private STETHID;

    ICurveMetapool public pool;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    uint256 public slippage; // = 100; //out of 10000. 100 = 1%

    address public stEth;

    // address public immutable weth;
    IWETH public constant weth =
        IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /*//////////////////////////////////////////////////////////////
                                INITIALIZATION
  //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    /**
     * @notice Initialize a new Lido Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param lidoInitData Encoded data for the Lido adapter initialization.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address _stEth, // 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
        bytes memory lidoInitData
    ) public initializer {
        __AdapterBase_init(adapterInitData);

        if (asset() != address(weth)) revert InvalidAsset();

        (
            address _pool,
            uint256 _wEthId,
            uint256 _stEthId,
            uint256 _slippage
        ) = abi.decode(lidoInitData, (address, uint256, uint256, uint256));

        stEth = _stEth;

        pool = ICurveMetapool(_pool);
        WETHID = _wEthId;
        STETHID = _stEthId;
        slippage = _slippage;

        _name = "VaultCraft stEth Adapter";
        _symbol = "vcStEth";

        IERC20(_stEth).approve(_pool, type(uint256).max);
    }

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

    // To receive eth from lido
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function _totalAssets() internal view override returns (uint256) {
        return IERC20(stEth).balanceOf(address(this)); // this can be higher than the total assets deposited due to staking rewards
    }

    /**
     * @notice Simulate the effects of a withdraw at the current block, given current on-chain conditions.
     * @dev Override this function if the underlying protocol has a unique withdrawal logic and/or withdraw fees.
     */
    function previewWithdraw(
        uint256 assets
    ) public view virtual override returns (uint256) {
        uint256 slippageAllowance = assets
            .mul(BPS_DENOMINATOR.add(slippage))
            .div(BPS_DENOMINATOR);
        // return StableSwapSTETH.get_dy(WETHID, STETHID, assets);
        return _convertToShares(slippageAllowance, Math.Rounding.Down);
    }

    /**
     * @notice Simulate the effects of a redeem at the current block, given current on-chain conditions.
     * @dev Override this function if the underlying protocol has a unique redeem logic and/or redeem fees.
     */
    function previewRedeem(
        uint256 shares
    ) public view virtual override returns (uint256) {
        uint256 slippageAllowance = shares
            .mul(BPS_DENOMINATOR.sub(slippage))
            .div(BPS_DENOMINATOR);
        // return StableSwapSTETH.get_dy(STETHID, WETHID, shares);
        return _convertToAssets(slippageAllowance, Math.Rounding.Down);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into LIDO pool
    function _protocolDeposit(
        uint256 assets,
        uint256
    ) internal virtual override {
        weth.withdraw(assets); // Grab native Eth from Weth contract
        ILido(stEth).submit{value: assets}(FEE_RECIPIENT); // Submit to Lido Contract
    }

    /// @notice Withdraw from LIDO pool
    function _protocolWithdraw(
        uint256 assets,
        uint256
    ) internal virtual override {
        uint256 slippageAllowance = assets.mulDiv(
            BPS_DENOMINATOR.sub(slippage),
            BPS_DENOMINATOR,
            Math.Rounding.Down
        );
        uint256 amountRecieved = pool.exchange(
            STETHID,
            WETHID,
            assets,
            slippageAllowance
        );
        weth.deposit{value: amountRecieved}(); // get wrapped eth back
    }
}
