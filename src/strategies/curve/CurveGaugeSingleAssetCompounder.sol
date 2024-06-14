// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../BaseStrategy.sol";
import {ICurveLp, IGauge, ICurveRouter, CurveSwap, IMinter} from "./ICurve.sol";
import {BaseCurveCompounder, CurveTradeLibrary} from "../../peripheral/BaseCurveCompounder.sol";

/**
 * @title   Curve Child Gauge Adapter
 * @notice  ERC4626 wrapper for  Curve Child Gauge Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/curvefi/curve-xchain-factory/blob/master/contracts/implementations/ChildGauge.vy.
 * Allows wrapping Curve Child Gauge Vaults.
 */
contract CurveGaugeSingleAssetCompounder is BaseStrategy, BaseCurveCompounder {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    address public lpToken;
    address public pool;

    IGauge public gauge;

    int128 public indexIn;
    uint256 public nCoins;

    uint256 public slippage;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoDeposit_ Controls if `protocolDeposit` gets called on deposit
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function initialize(address asset_, address owner_, bool autoDeposit_, bytes memory strategyInitData_)
        external
        initializer
    {
        (address _lpToken, address _pool, address _gauge, int128 _indexIn) =
            abi.decode(strategyInitData_, (address, address, address, int128));

        lpToken = _lpToken;
        pool = _pool;

        gauge = IGauge(_gauge);

        indexIn = _indexIn;
        nCoins = ICurveLp(_lpToken).N_COINS();

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(_lpToken).approve(_gauge, type(uint256).max);
        IERC20(asset()).approve(_lpToken, type(uint256).max);

        _name = string.concat("VaultCraft CurveGaugeSingleAssetCompounder ", IERC20Metadata(asset()).name(), " Adapter");
        _symbol = string.concat("vc-sccrv-", IERC20Metadata(asset()).symbol());
    }

    function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _name;
    }

    function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.
    function _totalAssets() internal view override returns (uint256) {
        uint256 lpBal = IERC20(address(gauge)).balanceOf(address(this));

        return lpBal > 0 ? ((ICurveLp(lpToken).get_virtual_price() * lpBal) / 1e18) : 0;
    }

    /// @notice The token rewarded from the convex reward contract
    function rewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets.mulDiv(10_000 - slippage, 10_000, Math.Rounding.Floor), Math.Rounding.Floor);
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil).mulDiv(10_000, 10_000 - slippage, Math.Rounding.Floor);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 assets, uint256, bytes memory data) internal override {
        CurveTradeLibrary.addLiquidity(
            pool, nCoins, uint256(uint128(indexIn)), assets, data.length > 0 ? abi.decode(data, (uint256)) : 0
        );

        gauge.deposit(IERC20(lpToken).balanceOf(address(this)));
    }

    function _protocolWithdraw(uint256 assets, uint256, bytes memory) internal override {
        uint256 lpWithdraw =
            IERC20(address(gauge)).balanceOf(address(this)).mulDiv(assets, _totalAssets(), Math.Rounding.Ceil);

        gauge.withdraw(lpWithdraw);

        ICurveLp(lpToken).remove_liquidity_one_coin(lpWithdraw, indexIn, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim rewards from the gauge
    function claim() internal override returns (bool success) {
        try gauge.claim_rewards() {
            success = true;
        } catch {}
    }

    /**
     * @notice Claim rewards and compound them into the vault
     */
    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        claim();

        sellRewardsViaCurve();

        // Slippage protection will be done here via `data` as the `minOut` of the `add_liquidity`-call
        _protocolDeposit(IERC20(asset()).balanceOf(address(this)), 0, data);

        emit Harvested();
    }

    function setHarvestValues(address newRouter, CurveSwap[] memory newSwaps, uint256 slippage_) external onlyOwner {
        setCurveTradeValues(newRouter, newSwaps);

        slippage = slippage_;
    }
}
