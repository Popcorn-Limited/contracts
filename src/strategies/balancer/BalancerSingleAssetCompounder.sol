// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "src/strategies/BaseStrategy.sol";
import {IMinter, IGauge, IPool, IBalancerVault, IBalancerQueries, ExitPoolRequest, JoinPoolRequest} from "src/interfaces/external/balancer/IBalancer.sol";
import {VaultReentrancyLib} from "src/interfaces/external/balancer/VaultReentrancyLib.sol";
import {BaseBalancerCompounder, TradePath} from "src/peripheral/BaseBalancerCompounder.sol";

/**
 * @title  Balancer single asset compounder
 * @author ADN
 * @notice ERC4626 wrapper for Balancer Vaults.
 *
 * An ERC4626 compliant Wrapper for Balancer
 */

struct InitValues {
    address minter;
    address gauge;
    address vault;
    uint256 assetIndex;
    uint256 userDataAssetIndex;
    uint256 amountsInLen;
    bytes32 poolId;
}

contract BalancerSingleAssetCompounder is BaseStrategy, BaseBalancerCompounder {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using VaultReentrancyLib for IBalancerVault;

    string internal _name;
    string internal _symbol;

    IMinter public minter;
    IGauge public gauge;
    IPool public pool;
    bytes32 poolId;
    IBalancerVault public vault;

    IBalancerQueries public constant queries = IBalancerQueries(address(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5));
    uint256 assetIndex; 
    uint256 userDataAssetIndex;
    uint256 amountsInUserDataLen;

    uint256 lastTotalAssets;
    uint256 lastUpdateBlock;

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
        __BaseStrategy_init(asset_, owner_, autoDeposit_);
        
        InitValues memory initValues = abi.decode(strategyInitData_, (InitValues));

        if (IGauge(initValues.gauge).is_killed()) revert Disabled();

        minter = IMinter(initValues.minter);
        gauge = IGauge(initValues.gauge);
        poolId = initValues.poolId;
        assetIndex = initValues.assetIndex;
        userDataAssetIndex = initValues.userDataAssetIndex;
        amountsInUserDataLen = initValues.amountsInLen;

        vault = IBalancerVault(initValues.vault);
        (address pool_, ) = vault.getPool(initValues.poolId);
        pool = IPool(pool_);

        // approve vault to pull asset
        IERC20(asset_).approve(initValues.vault, type(uint256).max);

        // approve gauge to pull LP token
        IERC20(address(pool)).approve(address(initValues.gauge), type(uint256).max);

        _name = string.concat("VaultCraft BalancerCompounder ", IERC20Metadata(asset()).name(), " Adapter");
        _symbol = string.concat("vc-bc-", IERC20Metadata(asset()).symbol());
    }

    function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _name;
    }

    function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    /////////////////////////////////////////////////////////////*/
    function _totalAssets() internal view override returns (uint256) {
        return lastTotalAssets;
    }

    function updateTotalAssets() external returns (uint256 newTotal){
        (address[] memory tokens,,) = vault.getPoolTokens(poolId);
        newTotal = _updateTotalAssets(tokens);
    }

    /// @notice The token rewarded
    function rewardTokens() external view override returns (address[] memory) {
        return _balancerSellTokens;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 assets, uint256, bytes memory) internal virtual override { 
        // add liquidity single token
        address[] memory tokens = _addLiquiditySingleToken(assets);

        // gauge deposit
        gauge.deposit(IERC20(address(pool)).balanceOf(address(this)));

        // update tot assets
        _updateTotalAssets(tokens);
    }

    function _protocolWithdraw(uint256 assets, uint256, bytes memory) internal virtual override {
        uint256 lpToWithdraw = gauge.balanceOf(address(this)).mulDiv(assets, _totalAssets(), Math.Rounding.Ceil);

        // unstake gauge
        gauge.withdraw(lpToWithdraw, false);

        // remove liquidity single token
        address[] memory tokens = _removeLiquiditySingleToken(lpToWithdraw, assets);

        // update total assets
        _updateTotalAssets(tokens);
    }
    
    // simulates a full withdrawal
    function _updateTotalAssets(address[] memory tokens) internal returns (uint256 newTotal) {
        uint256 lpBalance = gauge.balanceOf(address(this));
        if(lpBalance == 0) return 0;
        
        uint256[] memory minAmountsOut = new uint256[](tokens.length);
        minAmountsOut[assetIndex] = 0;
        
        bytes memory userData = abi.encode(0, lpBalance, userDataAssetIndex); // Exact BPT IN - single asset out
        
        ExitPoolRequest memory req = ExitPoolRequest(
            tokens,
            minAmountsOut,
            userData,
            false
        );

        (bool success, bytes memory data) = address(queries).call(
            abi.encodeWithSelector(
                IBalancerQueries.queryExit.selector, poolId, address(this), address(this), req
            )
        );

        if(!success) return lastTotalAssets; // maybe revert? todo

        (, uint256[] memory amountsOut) = abi.decode(data, (uint256, uint256[]));

        lastTotalAssets = amountsOut[assetIndex];
        newTotal = amountsOut[assetIndex];
        lastUpdateBlock = block.timestamp;

        // anti reentrancy todo
        vault.ensureNotInVaultContext();
    }

    function _addLiquiditySingleToken(uint256 assets) internal returns (address[] memory tokens) {
        (tokens,,) = vault.getPoolTokens(poolId);
   
        uint256[] memory amounts = new uint256[](tokens.length);
        amounts[assetIndex] = assets;

        uint256[] memory amountsUserData = new uint256[](amountsInUserDataLen);
        amountsUserData[userDataAssetIndex] = assets;

        bytes memory userData = abi.encode(1, amountsUserData, 0); // Exact In Enum, inAmounts, minOut

        JoinPoolRequest memory req = JoinPoolRequest(
            tokens,
            amounts,
            userData,
            false
        );

        vault.joinPool(
            poolId,
            address(this),
            address(this),
            req
        );
    }

    function _removeLiquiditySingleToken(uint256 lpToWithdraw, uint256 assets) internal returns (address[] memory tokens){
        (tokens,,) = vault.getPoolTokens(poolId);

        uint256[] memory minAmountsOut = new uint256[](tokens.length);
        minAmountsOut[assetIndex] = assets;

        bytes memory userData = abi.encode(0, lpToWithdraw, userDataAssetIndex); // Exact BPT IN - single asset out
        ExitPoolRequest memory req = ExitPoolRequest(
            tokens,
            minAmountsOut,
            userData,
            false
        );

        vault.exitPool(poolId, address(this), address(this), req);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    function claim() internal override returns (bool success) {
        try minter.mint(address(gauge)) {
            success = true;
        } catch {}
    }

    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        address[] memory tokens;
        (tokens,,) = vault.getPoolTokens(poolId);

        _updateTotalAssets(tokens);
        
        claim();

        address asset_ = asset();
        
        sellRewardsViaBalancer();
        
        _protocolDeposit(IERC20(asset_).balanceOf(address(this)), 0, bytes(""));

        emit Harvested();
    }

    function setHarvestValues(
        address newBalancerVault,
        TradePath[] memory newTradePaths
    ) external onlyOwner {
        setBalancerTradeValues(newBalancerVault, newTradePaths);
    }
}
