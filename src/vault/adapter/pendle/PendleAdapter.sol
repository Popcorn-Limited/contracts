// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter, IERC4626} from "../abstracts/AdapterBase.sol";
import {IPendleRouter, IPendleMarket, IPendleSYToken, IPendleOracle, ApproxParams, LimitOrderData, TokenInput, TokenOutput, SwapData} from "./IPendle.sol";

/**
 * @title   ERC4626 Pendle Protocol Vault Adapter
 * @author  ADN
 * @notice  ERC4626 wrapper for Pendle protocol
 *
 * An ERC4626 compliant Wrapper for Pendle Protocol.
 */
contract PendleAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IPendleRouter public pendleRouter;
    IPendleOracle public pendleOracle;
    address public pendleMarket;
    
    uint256 public lastRate;
    uint256 public slippage;
    uint32 public twapDuration; 

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error NotEndorsed();
    error InvalidAsset();

    /**
     * @notice Initialize a new generic Vault Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address _pendleRouter,
        bytes memory pendleInitData
    ) external virtual initializer {
        __AdapterBase_init(adapterInitData);

        address baseAsset = asset();

        _name = string.concat(
            "VaultCraft Pendle",
            IERC20Metadata(baseAsset).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-", IERC20Metadata(baseAsset).symbol());

        pendleRouter = IPendleRouter(_pendleRouter);
        pendleOracle = IPendleOracle(address(0x66a1096C6366b2529274dF4f5D8247827fe4CEA8));

        (pendleMarket, slippage, twapDuration) = abi.decode(pendleInitData, (address, uint256, uint32));
        
        (address pendleSYToken, ,) = IPendleMarket(pendleMarket).readTokens();

        // make sure base asset and market are compatible
        _validateAsset(pendleSYToken, baseAsset);

        // check that vault asset is among the tokens available to mint the SY token
        address[] memory validTokens = IPendleSYToken(pendleSYToken).getTokensIn();
        bool isValidMarket;
        
        for(uint256 i=0; i<validTokens.length; i++) {
            if (validTokens[i] == baseAsset){
                isValidMarket = true;
                break;
            }
        }

        if(!isValidMarket)
            revert InvalidAsset();  

        // and among the tokens to be redeemable from the SY token
        validTokens = IPendleSYToken(pendleSYToken).getTokensOut();
        isValidMarket = false;
        for(uint256 i=0; i<validTokens.length; i++) {
            if (validTokens[i] == baseAsset){
                isValidMarket = true;
                break;
            }
        }

        if(!isValidMarket)
            revert InvalidAsset();  

        // approve pendle router 
        IERC20(baseAsset).approve(_pendleRouter, type(uint256).max);

        // approve LP token for withdrawal
        IERC20(pendleMarket).approve(_pendleRouter, type(uint256).max);

        // initialize rate 
        refreshRate();
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

    // uses last stored rate to approximate total underlying
    function _totalAssets() internal view override returns (uint256 t) {
        uint256 totAssets = IERC20(pendleMarket).balanceOf(address(this)).mulDiv(lastRate, 1e18, Math.Rounding.Floor);

        // apply slippage
        t = totAssets - totAssets.mulDiv(slippage, 1e18, Math.Rounding.Floor);
    }

    function refreshRate() public virtual {
        // for some reason the call reverts if called multiple times within the same tx
        try pendleOracle.getLpToAssetRate(address(pendleMarket), twapDuration) returns (uint256 r) {
            lastRate = r;
        } catch {}
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        // params suggested by docs 
        ApproxParams memory approxParams = ApproxParams(
            0,
            type(uint256).max,
            0, 
            256,
            1e14
        );

        // Empty structs
        LimitOrderData memory limitOrderData;
        SwapData memory swapData;

        address asset = asset();
        TokenInput memory tokenInput = TokenInput(
            asset,
            amount,
            asset,
            address(0),
            swapData
        );

        pendleRouter.addLiquiditySingleToken(
            address(this), 
            pendleMarket, 
            0, 
            approxParams, 
            tokenInput, 
            limitOrderData
        );
    }

    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal virtual override {
        refreshRate();
        address asset = asset();

        // Empty structs
        LimitOrderData memory limitOrderData;
        SwapData memory swapData;
        
        TokenOutput memory tokenOutput = TokenOutput(
            asset,
            amount,
            asset,
            address(0),
            swapData
        );

        uint256 lpAmount = amount == totalAssets() 
            ? IERC20(pendleMarket).balanceOf(address(this)) 
            : amountToLp(amount + amount.mulDiv(slippage, 1e18, Math.Rounding.Floor));

        pendleRouter.removeLiquiditySingleToken(
            address(this), 
            pendleMarket, 
            lpAmount, 
            tokenOutput, 
            limitOrderData
        );
    }  

    function amountToLp(uint256 amount) internal returns (uint256) {
        return amount.mulDiv(1e18, lastRate, Math.Rounding.Floor);
    }

    function _validateAsset(address syToken, address baseAsset) internal {
        // check that vault asset is among the tokens available to mint the SY token
        address[] memory validTokens = IPendleSYToken(syToken).getTokensIn();
        bool isValidMarket;
        
        for(uint256 i=0; i<validTokens.length; i++) {
            if (validTokens[i] == baseAsset){
                isValidMarket = true;
                break;
            }
        }

        if(!isValidMarket)
            revert InvalidAsset();  

        // and among the tokens to be redeemable from the SY token
        validTokens = IPendleSYToken(syToken).getTokensOut();
        isValidMarket = false;
        for(uint256 i=0; i<validTokens.length; i++) {
            if (validTokens[i] == baseAsset){
                isValidMarket = true;
                break;
            }
        }

        if(!isValidMarket)
            revert InvalidAsset();  
    }
}