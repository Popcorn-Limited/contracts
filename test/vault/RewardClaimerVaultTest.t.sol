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
import { MockERC20 } from "../utils/mocks/MockERC20.sol";
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

    function test__set_reward_token() public {
        IERC20[] memory newRewardTokens = new IERC20[](1);
        newRewardTokens[0] = IERC20(address(new MockERC20("Reward Token", "RTKN", 18)));
        adapter.setRewardsToken(newRewardTokens);

        IERC20[] memory _rewardTokens = adapter.getRewardTokens();
        address _rewardToken = address(_rewardTokens[0]);

        assertEq(address(newRewardTokens[0]), _rewardToken);
    }

    function test__distribute_reward_token_to_strategy() public  {
        IERC20[] memory newRewardTokens = new IERC20[](1);
        newRewardTokens[0] = IERC20(address(new MockERC20("Reward Token", "RTKN", 18)));
        adapter.setRewardsToken(newRewardTokens);


        MockERC20 _rewardToken = MockERC20(address(adapter.getRewardTokens()[0]));
        //address _rewardToken = address(_rewardTokens[0]);

        _rewardToken.mint(address(this), 1000e18);
        _rewardToken.approve(address(adapter), 1000e18);
        MockRewardClaimerStrategy(address(adapter)).updateRewardIndex(_rewardToken, 1000e18);
    }

    function test__deposit_from_user_to_vault_to_strategy(uint128 fuzzAmount) public  {
        IERC20[] memory newRewardTokens = new IERC20[](1);
        newRewardTokens[0] = IERC20(address(new MockERC20("Reward Token", "RTKN", 18)));
        adapter.setRewardsToken(newRewardTokens);

        //deposit 500 from alice
        uint256 aliceAssetAmount = 500;//bound(uint256(fuzzAmount), 1, _getVaultConfig().depositLimit);
        asset.mint(alice, aliceAssetAmount);
        vm.prank(alice);

        asset.approve(address(vault), aliceAssetAmount);
        vm.prank(alice);
        uint256 aliceShareAmount = vault.deposit(aliceAssetAmount, alice);

        //deposit 500 from bob
        uint256 bobAssetAmount = 500;//bound(uint256(fuzzAmount), 1, _getVaultConfig().depositLimit);
        asset.mint(bob, bobAssetAmount);

        vm.prank(bob);
        asset.approve(address(vault), bobAssetAmount);

        vm.prank(bob);
        uint256 bobShareAmount = vault.deposit(bobAssetAmount, alice);

        MockERC20 _rewardToken = MockERC20(address(adapter.getRewardTokens()[0]));
        _rewardToken.mint(address(this), 1000e18);
        _rewardToken.approve(address(adapter), 1000e18);
        MockRewardClaimerStrategy(address(adapter)).updateRewardIndex(_rewardToken, 1000e18);

        vm.prank(bob);
        RewardClaimerVault(address(vault)).getReward();
    }

    //TODO: Add test cases for the following
    //1. Add test cases for disturbing reward to MockStrategy - done, needs refactoring
    //2. Track deposits for vaults in MockStrategy -
    //3. Track deposits for users in vaults
    //4. Add test cases for vault to withdraw reward from strategy
    //5. Add test cases for users to withdraw reward from vault
    //6/ Accrue reward from strategy back into vault and then withdraw user reward
}
