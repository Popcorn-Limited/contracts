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

    uint256 private constant WETHID = 0;
    uint256 private constant STETHID = 1;
    ICurveMetapool public constant StableSwapSTETH =
        ICurveMetapool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    uint256 public constant DENOMINATOR = 10000;
    uint256 public slippage; // = 100; //out of 10000. 100 = 1%

    /// @notice The poolId inside Convex booster for relevant Curve lpToken.
    uint256 public pid;

    /// @notice The booster address for Convex
    ILido public lido;

    // address public immutable weth;
    IWETH public weth;

    address private referal = address(0); //stratms. for recycling and redepositing

    // We need to figure out how to get this referral

    /*//////////////////////////////////////////////////////////////
                                INITIALIZATION
  //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize a new Lido Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param lidoInitData Encoded data for the Lido adapter initialization.
     * @dev `_lidoAddress` - The vault address for Lido.
     * @dev `_pid` - The poolId for lpToken.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address _wethAddress,
        bytes memory lidoInitData
    ) public initializer {
        __AdapterBase_init(adapterInitData);

        (address _lidoAddress, uint256 _pid) = abi.decode(
            lidoInitData,
            (address, uint256)
        );

        lido = ILido(ILido(_lidoAddress).token());
        pid = _pid;
        weth = IWETH(ILido(_lidoAddress).weth());
        slippage = 100;

        _name = string.concat(
            "Popcorn Lido ",
            IERC20Metadata(address(weth)).name(),
            " Adapter"
        );
        _symbol = string.concat(
            "popL-",
            IERC20Metadata(address(weth)).symbol()
        );

        IERC20(address(lido)).approve(address(lido), type(uint256).max);
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

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into LIDO pool
    function _protocolDeposit(
        uint256 assets,
        uint256
    ) internal virtual override {
        weth.withdraw(assets); // Grab native Eth from Weth contract
        lido.submit{value: assets}(referal); // Submit to Lido Contract
    }

    /// @notice Withdraw from LIDO pool
    function _protocolWithdraw(
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        uint256 slippageAllowance = assets.mulDiv(
            DENOMINATOR.sub(slippage),
            DENOMINATOR,
            Math.Rounding.Down
        );
        uint256 amountRecieved = StableSwapSTETH.exchange(
            STETHID,
            WETHID,
            assets,
            slippageAllowance
        );
        weth.deposit{value: amountRecieved}(); // get wrapped eth back
    }

    /**
     * @notice Simulate the effects of a withdraw at the current block, given current on-chain conditions.
     * @dev Override this function if the underlying protocol has a unique withdrawal logic and/or withdraw fees.
     */
    function previewWithdraw(
        uint256 assets
    ) public view virtual override returns (uint256) {
        uint256 slippageAllowance = assets.mul(DENOMINATOR.add(slippage)).div(
            DENOMINATOR
        );
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
        uint256 slippageAllowance = shares.mul(DENOMINATOR.sub(slippage)).div(
            DENOMINATOR
        );
        // return StableSwapSTETH.get_dy(STETHID, WETHID, shares);
        return _convertToAssets(slippageAllowance, Math.Rounding.Down);
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

    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        return
            assets.mulDiv(
                totalSupply() + 10 ** decimalOffset,
                totalAssets() + 1,
                rounding
            );
    }

    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        return
            shares.mulDiv(
                totalAssets() + 1,
                totalSupply() + 10 ** decimalOffset,
                rounding
            );
    }
}
