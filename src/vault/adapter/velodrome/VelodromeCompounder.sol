// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {IGauge, ILpToken, Route, ISolidlyRouter} from "./IVelodrome.sol";
import {IPermissionRegistry} from "../../../interfaces/vault/IPermissionRegistry.sol";

/**
 * @title   Velodrome Adapter
 * @author  amatureApe
 * @notice  ERC4626 wrapper for Velodrome Vaults.
 *
 * Allows wrapping Velodrome Vaults.
 */
contract VelodromeCompounder is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The Velodrome contract
    IGauge public gauge;

    address internal _rewardToken;
    address[] internal _rewardTokens;

    address[2] internal lpTokens;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error NotEndorsed(address gauge);
    error InvalidAsset();

    /**
     * @notice Initialize a new Velodrome Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry - PermissionRegistry to verify the gauge
     * @param velodromeInitData - init data for velo adatper
     * @dev `_gauge` - the gauge address to stake our asset in
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory velodromeInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        (address _gauge, address _solidlyRouter) = abi.decode(
            velodromeInitData,
            (address, address)
        );

        if (!IPermissionRegistry(registry).endorsed(_gauge))
            revert NotEndorsed(_gauge);

        gauge = IGauge(_gauge);

        if (gauge.stakingToken() != asset()) revert InvalidAsset();

        address rewardToken = gauge.rewardToken(); // velo
        _rewardToken = rewardToken;
        _rewardTokens.push(rewardToken);

        (address lp0, address lp1) = ILpToken(asset()).tokens();
        lpTokens[0] = lp0;
        lpTokens[1] = lp1;

        _name = string.concat(
            "VaultCraft Velodrome ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcVelo-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).approve(address(gauge), type(uint256).max);
        IERC20(rewardToken).approve(_solidlyRouter, type(uint256).max);
        IERC20(lp0).approve(_solidlyRouter, type(uint256).max);
        IERC20(lp1).approve(_solidlyRouter, type(uint256).max);
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

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.
    function _totalAssets() internal view override returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 amount, uint256) internal override {
        gauge.deposit(amount);
    }

    function _protocolWithdraw(uint256 amount, uint256) internal override {
        gauge.withdraw(amount);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim rewards from the Velodrome gauge
    function claim() public override returns (bool success) {
        try gauge.getReward(address(this)) {
            success = true;
        } catch {}
    }

    /// @notice The tokens rewarded
    function rewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    function harvest() public override takeFees {
        if ((lastHarvest + harvestCooldown) < block.timestamp) {
            claim();

            uint256 rewardBal = gauge.earned(address(this));
            if (rewardBal >= minTradeAmount) {
                // Trade to lpAssets
                trade();

                uint256 amount0 = IERC20(lpTokens[0]).balanceOf(address(this));
                uint256 amount1 = IERC20(lpTokens[1]).balanceOf(address(this));

                if (amount0 > 0 && amount1 > 0) {
                    // Pool assets
                    ISolidlyRouter(solidlyRouter).addLiquidity(
                        lpTokens[0],
                        lpTokens[1],
                        false,
                        amount0,
                        amount1,
                        1,
                        1,
                        address(this),
                        block.timestamp
                    );
                }

                uint256 depositAmount = IERC20(asset()).balanceOf(
                    address(this)
                );
                if (depositAmount > 0) {
                    // redeposit
                    _protocolDeposit(depositAmount, 0);
                }
            }

            lastHarvest = block.timestamp;
        }

        emit Harvested();
    }

    function trade() internal {
        uint256 outputBal = IERC20(_rewardToken).balanceOf(address(this));
        uint256 amount = outputBal / 2;

        for (uint256 i; i < 2; i++) {
            if (i == 1) amount = outputBal - amount;
            if (lpTokens[i] != _rewardToken) {
                ISolidlyRouter(solidlyRouter).swapExactTokensForTokens(
                    amount,
                    0,
                    routes[lpTokens[i]],
                    address(this),
                    block.timestamp
                );
            }
        }
    }

    mapping(address => Route[]) routes;
    uint256 internal minTradeAmount;
    address internal solidlyRouter;

    function setHarvestValues(
        Route[][2] memory routes_,
        uint256 minTradeAmount_,
        address solidlyRouter_
    ) external onlyOwner {
        _setRoute(lpTokens[0], routes_[0]);
        _setRoute(lpTokens[1], routes_[1]);

        minTradeAmount = minTradeAmount_;
        solidlyRouter = solidlyRouter_;
    }

    function _setRoute(address key, Route[] memory routes_) internal {
        uint256 storageLen = routes[key].length;
        uint256 len = routes_.length;
        for (uint256 i; i < len; i++) {
            if (i >= storageLen) {
                routes[key].push(routes_[i]);
            } else {
                routes[key][i] = routes_[i];
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                      EIP-165 LOGIC
  //////////////////////////////////////////////////////////////*/

    function supportsInterface(
        bytes4 interfaceId
    ) public pure override(WithRewards, AdapterBase) returns (bool) {
        return
            interfaceId == type(IWithRewards).interfaceId ||
            interfaceId == type(IAdapter).interfaceId;
    }
}
