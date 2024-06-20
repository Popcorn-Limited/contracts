// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "src/strategies/BaseStrategy.sol";
import {Route, IGauge} from "src/interfaces/external/velodrome/IVelodrome.sol";
import {BaseVelodromeLpCompounder, SwapStep, ILpToken} from "src/peripheral/BaseVelodromeLpCompounder.sol";

/**
 * @title  Velodrome Adapter
 * @author ADN
 * @notice ERC4626 wrapper for Velodrome Vaults.
 *
 * An ERC4626 compliant Wrapper for Velodrome protocol
 * Takes a pool LP token as deposit, compound rewards into more LP tokens.
 */
contract VelodromeLPCompounder is BaseStrategy, BaseVelodromeLpCompounder {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IGauge gauge;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();
    error Disabled();

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
        (address gauge_) = abi.decode(strategyInitData_, (address));

        gauge = IGauge(gauge_);

        if(gauge.stakingToken() != asset_) revert InvalidAsset();

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(asset_).approve(gauge_, type(uint256).max);

        _name = string.concat("VaultCraft Velodrome Compounder ", IERC20Metadata(asset()).name(), " Adapter");
        _symbol = string.concat("vc-velo-", IERC20Metadata(asset()).symbol());
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

    function _totalAssets() internal view override returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    /// @notice The token rewarded
    function rewardTokens() external view override returns (address[] memory) {
        return velodromeSellTokens;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 assets, uint256, bytes memory) internal virtual override {
        gauge.deposit(assets);
    }

    function _protocolWithdraw(uint256 assets, uint256, bytes memory) internal virtual override {
        gauge.withdraw(assets);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    function claim() internal override returns (bool success) {
        try gauge.getReward(address(this)) {
            success = true;
        } catch {}
    }

    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        claim();

        // caching
        address asset_ = asset();

        sellRewardsForLpTokenViaVelodrome(asset_, data);

        _protocolDeposit(IERC20(asset_).balanceOf(address(this)), 0, bytes(""));

        emit Harvested();
    }

    // allow owner to withdraw eventual dust amount of tokens
    // from the compounding operation
    function withdrawDust(address token) external onlyOwner {
        (address tokenA, address tokenB) = ILpToken(asset()).tokens();
        
        if (token != tokenA && token != tokenB) {
            revert("Invalid Token");
        }

        IERC20(token).safeTransfer(owner, IERC20(token).balanceOf(address(this)));
    }

    function setHarvestValues(
        address newVelodromeVault,
        address[] memory rewTokens,
        SwapStep[] memory newTradePaths
    ) external onlyOwner {
        setVelodromeLpCompounderValues(newVelodromeVault, asset(), rewTokens, newTradePaths);
    }
}
