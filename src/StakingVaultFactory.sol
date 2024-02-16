pragma solidity ^0.8.0;

import {StakingVault} from "./vaults/StakingVault.sol";

contract StakingVaultFactory {
    address[] public allVaults;

    event VaultDeployed(address indexed asset);

    function deploy(
        address asset,
        address[] memory rewardTokens,
        address strategy,
        uint256 maxLockTime,
        string memory name,
        string memory symbol
    ) external {
        StakingVault vault = new StakingVault(
            asset,
            rewardTokens,
            strategy,
            maxLockTime,
            name,
            symbol
        );
        allVaults.push(address(vault));

        emit VaultDeployed(asset);
    }

    function getTotalVaults() external view returns (uint256) {
        return allVaults.length;
    }

    function getRegisteredAddresses() external view returns (address[] memory) {
        return allVaults;
    }
}
