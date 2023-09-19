// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {
    IERC20,
    Clones,
    IVault,
    VaultFees,
    MockERC20,
    BaseVaultTest,
    MockStrategyV2,
    BaseVaultConfig,
    AdapterConfig, ProtocolConfig
} from "../base/BaseVaultTest.sol";
import {
    SafeERC20Upgradeable as SafeERC20
} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../../../../src/vault/v2/vaults/SingleStrategyVault.sol";

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
            owner: address(this)
        });

        ProtocolConfig memory protocolConfig = ProtocolConfig({
            registry: address (0),
            protocolInitData: abi.encode()
        });

        address adapterAddress = Clones.clone(adapterImplementation);
        MockStrategyV2(adapterAddress).__MockAdapter_init(adapterConfig, protocolConfig);
        return MockStrategyV2(adapterAddress);
    }

    function _createVault() internal override returns (IVault) {
        if(vaultImplementation == address(0)) {
            vaultImplementation = address(new SingleStrategyVault());
        }
        return IVault(Clones.clone(vaultImplementation));
    }

    function _getVaultConfig() internal override returns(BaseVaultConfig memory) {
        return BaseVaultConfig ({
            asset_: IERC20(address(asset)),
            fees: VaultFees({
                deposit: 100,
                withdrawal: 100,
                management: 100,
                performance: 100
            }),
            feeRecipient: feeRecipient,
            depositLimit: 0,
            owner: bob,
            protocolOwner: bob,
            name: "VaultCraft SingleStrategyVault"
        });
    }
}
