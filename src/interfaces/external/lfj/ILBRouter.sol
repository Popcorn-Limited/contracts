// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.0
pragma solidity ^0.8.25;

interface ILBRouter {
    /**
     * @dev The liquidity parameters, such as:
     * - tokenX: The address of token X
     * - tokenY: The address of token Y
     * - binStep: The bin step of the pair
     * - amountX: The amount to send of token X
     * - amountY: The amount to send of token Y
     * - amountXMin: The min amount of token X added to liquidity
     * - amountYMin: The min amount of token Y added to liquidity
     * - activeIdDesired: The active id that user wants to add liquidity from
     * - idSlippage: The number of id that are allowed to slip
     * - deltaIds: The list of delta ids to add liquidity (`deltaId = activeId - desiredId`)
     * - distributionX: The distribution of tokenX with sum(distributionX) = 1e18 (100%) or 0 (0%)
     * - distributionY: The distribution of tokenY with sum(distributionY) = 1e18 (100%) or 0 (0%)
     * - to: The address of the recipient
     * - refundTo: The address of the recipient of the refunded tokens if too much tokens are sent
     * - deadline: The deadline of the transaction
     */
    struct LiquidityParameters {
        address tokenX;
        address tokenY;
        uint256 binStep;
        uint256 amountX;
        uint256 amountY;
        uint256 amountXMin;
        uint256 amountYMin;
        uint256 activeIdDesired;
        uint256 idSlippage;
        int256[] deltaIds;
        uint256[] distributionX;
        uint256[] distributionY;
        address to;
        address refundTo;
        uint256 deadline;
    }

    /**
     * @notice Add liquidity while performing safety checks
     * @dev This function is compliant with fee on transfer tokens
     * @param liquidityParameters The liquidity parameters
     * @return amountXAdded The amount of token X added
     * @return amountYAdded The amount of token Y added
     * @return amountXLeft The amount of token X left (sent back to liquidityParameters.refundTo)
     * @return amountYLeft The amount of token Y left (sent back to liquidityParameters.refundTo)
     * @return depositIds The ids of the deposits
     * @return liquidityMinted The amount of liquidity minted
     */
    function addLiquidity(
        LiquidityParameters calldata liquidityParameters
    )
        external
        returns (
            uint256 amountXAdded,
            uint256 amountYAdded,
            uint256 amountXLeft,
            uint256 amountYLeft,
            uint256[] memory depositIds,
            uint256[] memory liquidityMinted
        );

    /**
     * @notice Add liquidity with NATIVE while performing safety checks
     * @dev This function is compliant with fee on transfer tokens
     * @param liquidityParameters The liquidity parameters
     * @return amountXAdded The amount of token X added
     * @return amountYAdded The amount of token Y added
     * @return amountXLeft The amount of token X left (sent back to liquidityParameters.refundTo)
     * @return amountYLeft The amount of token Y left (sent back to liquidityParameters.refundTo)
     * @return depositIds The ids of the deposits
     * @return liquidityMinted The amount of liquidity minted
     */
    function addLiquidityNATIVE(
        LiquidityParameters calldata liquidityParameters
    )
        external
        payable
        returns (
            uint256 amountXAdded,
            uint256 amountYAdded,
            uint256 amountXLeft,
            uint256 amountYLeft,
            uint256[] memory depositIds,
            uint256[] memory liquidityMinted
        );

    /**
     * @notice Remove liquidity while performing safety checks
     * @dev This function is compliant with fee on transfer tokens
     * @param tokenX The address of token X
     * @param tokenY The address of token Y
     * @param binStep The bin step of the LBPair
     * @param amountXMin The min amount to receive of token X
     * @param amountYMin The min amount to receive of token Y
     * @param ids The list of ids to burn
     * @param amounts The list of amounts to burn of each id in `_ids`
     * @param to The address of the recipient
     * @param deadline The deadline of the tx
     * @return amountX Amount of token X returned
     * @return amountY Amount of token Y returned
     */
    function removeLiquidity(
        address tokenX,
        address tokenY,
        uint16 binStep,
        uint256 amountXMin,
        uint256 amountYMin,
        uint256[] memory ids,
        uint256[] memory amounts,
        address to,
        uint256 deadline
    ) external returns (uint256 amountX, uint256 amountY);

    /**
     * @notice Remove NATIVE liquidity while performing safety checks
     * @dev This function is **NOT** compliant with fee on transfer tokens.
     * This is wanted as it would make users pays the fee on transfer twice,
     * use the `removeLiquidity` function to remove liquidity with fee on transfer tokens.
     * @param token The address of token
     * @param binStep The bin step of the LBPair
     * @param amountTokenMin The min amount to receive of token
     * @param amountNATIVEMin The min amount to receive of NATIVE
     * @param ids The list of ids to burn
     * @param amounts The list of amounts to burn of each id in `_ids`
     * @param to The address of the recipient
     * @param deadline The deadline of the tx
     * @return amountToken Amount of token returned
     * @return amountNATIVE Amount of NATIVE returned
     */
    function removeLiquidityNATIVE(
        address token,
        uint16 binStep,
        uint256 amountTokenMin,
        uint256 amountNATIVEMin,
        uint256[] memory ids,
        uint256[] memory amounts,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountNATIVE);
}
