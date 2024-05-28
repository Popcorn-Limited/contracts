// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../BaseStrategy.sol";
import {ICurveLp, IGauge, ICurveRouter, CurveSwap, IMinter} from "./ICurve.sol";
import {BaseCurveLpCompounder} from "../../peripheral/BaseCurveLpCompounder.sol";

/**
 * @title   Curve Child Gauge Adapter
 * @notice  ERC4626 wrapper for  Curve Child Gauge Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/curvefi/curve-xchain-factory/blob/master/contracts/implementations/ChildGauge.vy.
 * Allows wrapping Curve Child Gauge Vaults.
 */
contract CurveGaugeCompounder is BaseStrategy, BaseCurveLpCompounder {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IMinter internal minter;
    ICurveLp public pool;
    IGauge public gauge;
    uint256 internal nCoins;

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
        (address _gauge, address _pool, address _minter) = abi.decode(strategyInitData_, (address, address, address));

        minter = IMinter(_minter);
        gauge = IGauge(_gauge);
        pool = ICurveLp(_pool);

        nCoins = pool.N_COINS();

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(asset()).approve(_gauge, type(uint256).max);

        _name = string.concat("VaultCraft CurveGaugeCompounder ", IERC20Metadata(asset()).name(), " Adapter");
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
        return IERC20(address(gauge)).balanceOf(address(this));
    }

    /// @notice The token rewarded from the convex reward contract
    function rewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 assets, uint256, bytes memory) internal override {
        gauge.deposit(assets);
    }

    function _protocolWithdraw(uint256 assets, uint256, bytes memory) internal override {
        gauge.withdraw(assets);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim rewards from the gauge
    function claim() internal override returns (bool success) {
        try gauge.claim_rewards() {
            try minter.mint(address(gauge)) {
                success = true;
            } catch {}
        } catch {}
    }

    /**
     * @notice Claim rewards and compound them into the vault
     */
    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        claim();

        sellRewardsForLpTokenViaCurve(address(pool), asset(), nCoins, data);

        _protocolDeposit(IERC20(asset()).balanceOf(address(this)), 0, bytes(""));

        emit Harvested();
    }

    function setHarvestValues(address newRouter, CurveSwap[] memory newSwaps, int128 indexIn_) external onlyOwner {
        setCurveLpCompounderValues(newRouter, newSwaps, address(pool), indexIn_);
    }
}
