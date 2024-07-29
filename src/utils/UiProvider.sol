// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {MultiStrategyVault} from "src/vaults/MultiStrategyVault.sol";

struct DynamicValue {
    uint256 a;
    uint256 b;
    uint256 c;
}

/**
 * @title   UiProvider
 * @author  RedVeil
 * @notice
 */
contract UiProvider {
    function getDynamicVaultValues(
        address[] memory vaults
    ) external view returns (DynamicValue[] memory) {
        uint256 len = vaults.length;
        DynamicValue[] memory result = new DynamicValue[](len);

        for (uint256 i; i < len; i++) {
            result[i] = DynamicValue({
                a: MultiStrategyVault(vaults[i]).totalAssets(),
                b: MultiStrategyVault(vaults[i]).totalSupply(),
                c: MultiStrategyVault(vaults[i]).depositLimit()
            });
        }
        return result;
    }

    function getStrategyValues(
        address[] memory vaults
    ) external view returns (DynamicValue[] memory) {
        uint256 len = vaults.length;
        DynamicValue[] memory result = new DynamicValue[][](len);

        for (uint256 i; i < len; i++) {
            IERC4626[] strategies = MultiStrategyVault(vaults[i])
                .getStrategies();
            uint256 stratLen = strategies.length;
            DynamicValue[] memory stratVals = new DynamicValue[](stratLen);

            for (uint256 n; n < stratLen; n++) {
                uint256 ta = IERC4626(strategies[n]).totalAssets();
                uint256 ts = IERC4626(strategies[n]).totalSupply();
                uint256 vaultBal = IERC20(strategies[n]).balanceOf(vaults[i]);

                uint256 allocation = IERC4626(strategies[n]).convertToAssets(
                    vaultBal
                );
                stratVals[n] = DynamicValue({a: ta, b: ts, c: allocation});
            }
            result[i] = stratVals;
        }
        return result;
    }
}
