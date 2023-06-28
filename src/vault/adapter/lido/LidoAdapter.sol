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
    
    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;
    ICurveMetapool public constant StableSwapSTETH =
        ICurveMetapool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    uint256 public constant DENOMINATOR = 10000;
    uint256 public slippage; // = 100; //out of 10000. 100 = 1%

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
        address _lidoAddress,
        bytes memory lidoInitData
    ) public initializer {
        __AdapterBase_init(adapterInitData);

        (,uint256 _pid) = abi.decode(
            lidoInitData,
            (address, uint256)
        );
        
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
    function _underlyingBalance() internal view returns (uint256) {
        return lido.sharesOf(address(this));
    }

    function _totalAssets() internal view override returns (uint256) {
        return IERC20(stEth).balanceOf(address(this)); // this can be higher than the total assets deposited due to staking rewards
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
    
    /**
     * @notice Withdraws `assets` from the underlying protocol and burns vault shares from `owner`.
     * @dev Executes harvest if `harvestCooldown` is passed since last invocation.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        uint256 balanceInitial = IERC20(asset()).balanceOf(address(this));

        if (!paused()) {
            _protocolWithdraw(assets, shares);
        }

        _burn(owner, shares);

        uint256 balanceNow = IERC20(asset()).balanceOf(address(this));

        uint256 amountReceived = balanceNow.sub(balanceInitial);

        IERC20(asset()).safeTransfer(receiver, amountReceived);

        harvest();

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
