// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter, IERC4626} from "../abstracts/AdapterBase.sol";
import {IPendleRouter, IwstETH, IPendleMarket, IPendleSYToken, IPendleOracle, ApproxParams, LimitOrderData, TokenInput, TokenOutput, SwapData} from "./IPendle.sol";
import {PendleAdapter} from "./PendleAdapter.sol";

/**
 * @title   ERC4626 Pendle Protocol Vault Adapter
 * @author  ADN
 * @notice  ERC4626 wrapper for Pendle protocol
 *
 * An ERC4626 compliant Wrapper for Pendle Protocol.
 * Only with wstETH base asset
 */
contract PendleWstETHAdapter is PendleAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize a new generic wstETH Pendle Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address _pendleRouter,
        bytes memory pendleInitData
    ) external initializer override (PendleAdapter) {
        __AdapterBase_init(adapterInitData);

        address baseAsset = asset();
        require(baseAsset == 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, 'Only wstETH');

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

        // approve base asset for deposit 
        IERC20(baseAsset).approve(_pendleRouter, type(uint256).max);

        // approve LP token for withdrawal
        IERC20(pendleMarket).approve(_pendleRouter, type(uint256).max);

        // initialize lp to asset rate 
        refreshRate();
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function refreshRate() public override (PendleAdapter) {
        // for some reason the call reverts if called multiple times within the same tx
        try pendleOracle.getLpToAssetRate(address(pendleMarket), twapDuration) returns (uint256 r) {
            // if using wsteth, the rate returned by pendle is against eth
            // need to apply eth/wsteth rate as well
            uint256 ethRate = IwstETH(asset()).getWstETHByStETH(1 ether);
            lastRate = r.mulDiv(ethRate, 1e18, Math.Rounding.Floor);
        } catch {}
    }
}