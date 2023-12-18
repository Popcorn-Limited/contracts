// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";

import {
    IERC20,
    BaseVaultTest
} from "../base/BaseVaultTest.sol";
import {MockERC20} from "../utils/mocks/MockERC20.sol";
import {IVault, VaultFees} from "../../src/base/interfaces/IVault.sol";
import {BaseVaultConfig} from "../../src/base/BaseVault.sol";
import {AdapterConfig} from "../../src/base/interfaces/IBaseAdapter.sol";
import {MockStrategyV2} from "../utils/mocks/MockStrategyV2.sol";
import {
    SafeERC20Upgradeable as SafeERC20
} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {SingleStrategyVault} from "../../src/vaults/SingleStrategyVault.sol";

contract SingleStrategyVaultTest is BaseVaultTest {
    IERC20[] public rewardTokens;

    function _createAdapter() internal override returns (MockStrategyV2) {
        if(adapterImplementation == address(0)) {
            adapterImplementation = address(new MockStrategyV2());
        }

        AdapterConfig memory adapterConfig = AdapterConfig({
            underlying: IERC20(address(asset)),
            lpToken: IERC20(address(0)),
            useLpToken: false,
            rewardTokens: rewardTokens,
            owner: address(this),
            protocolData: ""
        });

        address adapterAddress = Clones.clone(adapterImplementation);
        MockStrategyV2(adapterAddress).__MockAdapter_init(adapterConfig);
        return MockStrategyV2(adapterAddress);
    }

    function _createVault() internal override returns (IVault) {
        if(vaultImplementation == address(0)) {
            vaultImplementation = address(new SingleStrategyVault());
        }
        return IVault(Clones.clone(vaultImplementation));
    }

    function _getVaultConfig() internal view override returns(BaseVaultConfig memory) {
        return BaseVaultConfig ({
            asset_: IERC20(address(asset)),
            fees: VaultFees({
                deposit: 100,
                withdrawal: 0,
                management: 100,
                performance: 100
            }),
            feeRecipient: feeRecipient,
            depositLimit: 1000,
            owner: bob,
            protocolOwner: bob,
            name: "VaultCraft SingleStrategyVault"
        });
    }
}
