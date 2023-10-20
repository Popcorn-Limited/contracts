// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {
    IERC20,
    Clones,
    IVault,
    VaultFees,
    BaseVaultTest,
    MockStrategy,
    BaseVaultConfig,
    AdapterConfig, ProtocolConfig
} from "../base/BaseVaultTest.sol";
import {
    SafeERC20Upgradeable as SafeERC20
} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {RewardClaimerVault} from "../../src/vaults/RewardClaimerVault.sol";
import {MockRewardClaimerStrategy} from "../utils/mocks/MockRewardClaimerStrategy.sol";

contract RewardClaimerVaultTest is BaseVaultTest {
    IERC20[] public rewardTokens;

    function _createAdapter() internal override returns (MockStrategy) {
        if(adapterImplementation == address(0)) {
            adapterImplementation = address(new MockRewardClaimerStrategy());
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
        MockRewardClaimerStrategy(adapterAddress)
            .__MockRewardClaimerStrategy_init(adapterConfig, protocolConfig);
        return MockRewardClaimerStrategy(adapterAddress);
    }

    function _createVault() internal override returns (IVault) {
        if(vaultImplementation == address(0)) {
            vaultImplementation = address(new RewardClaimerVault());
        }
        return IVault(Clones.clone(vaultImplementation));
    }

    function _getVaultConfig() internal override returns(BaseVaultConfig memory) {
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

    //TODO: Add test cases for the following
    //1. Add test cases for disturbing reward to MockStrategy
    //2. Track deposits for users in vaults and for vaults in strategies
    //3. Add test cases for vault to withdraw reward from strategy
    //4. Add test cases for users to withdraw reward from vault
}
