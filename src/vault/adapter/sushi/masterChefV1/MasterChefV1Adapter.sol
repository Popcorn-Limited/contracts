// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../../abstracts/WithRewards.sol";
import {IMasterChefV1} from "./IMasterChefV1.sol";

/**
 * @title   MasterChefV1 Adapter
 * @notice  ERC4626 wrapper for MasterChefV1 Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/sushiswap/sushiswap/blob/archieve/canary/contracts/MasterChef.sol.
 * Allows wrapping MasterChefV1 Vaults.
 */
contract MasterChefV1Adapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    // @notice The MasterChef contract
    IMasterChefV1 public masterChef;

    // @notice The address of the reward token
    address public rewardsToken;

    // @notice The pool ID
    uint256 public pid;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    /**
     * @notice Initialize a new MasterChef Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev `_pid` - The poolId for lpToken.
     * @dev `_rewardsToken` - The token rewarded by the MasterChef contract (Sushi, Cake...)
     * @dev This function is called by the factory contract when deploying a new vault.
     */

    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory masterchefInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        (uint256 _pid, address _rewardsToken) = abi.decode(
            masterchefInitData,
            (uint256, address)
        );

        masterChef = IMasterChefV1(registry);
        IMasterChefV1.PoolInfo memory pool = masterChef.poolInfo(_pid);

        if (pool.lpToken != asset()) revert InvalidAsset();

        pid = _pid;
        rewardsToken = _rewardsToken;

        _name = string.concat(
            "VaultCraft MasterChefV1 ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcMcV1-", IERC20Metadata(asset()).symbol());

        IERC20(pool.lpToken).approve(address(masterChef), type(uint256).max);
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

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.

    function _totalAssets() internal view override returns (uint256) {
        IMasterChefV1.UserInfo memory user = masterChef.userInfo(
            pid,
            address(this)
        );
        return user.amount;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 amount, uint256) internal override {
        masterChef.deposit(pid, amount);
    }

    function _protocolWithdraw(uint256 amount, uint256) internal override {
        masterChef.withdraw(pid, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Claim rewards from the masterChef
    function claim() public override onlyStrategy returns (bool success) {
        try masterChef.deposit(pid, 0) {
            success = true;
        } catch {}
    }

    /// @notice The token rewarded
    function rewardTokens()
        external
        view
        override
        returns (address[] memory _rewardTokens)
    {
        _rewardTokens = new address[](1);
        _rewardTokens[0] = rewardsToken;
    }

    /*//////////////////////////////////////////////////////////////
                      EIP-165 LOGIC
  //////////////////////////////////////////////////////////////*/

    function supportsInterface(
        bytes4 interfaceId
    ) public pure override(WithRewards, AdapterBase) returns (bool) {
        return
            interfaceId == type(IWithRewards).interfaceId ||
            interfaceId == type(IAdapter).interfaceId;
    }
}
