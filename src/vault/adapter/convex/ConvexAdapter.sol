// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {IConvexBooster, IConvexRewards, IRewards} from "./IConvex.sol";

/**
 * @title   Convex Adapter
 * @author  amatureApe
 * @notice  ERC4626 wrapper for Convex Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/convex-eth/platform/blob/main/contracts/contracts/Booster.sol.
 * Allows wrapping Convex Vaults with or without an active convexBooster.
 * Allows for additional strategies to use rewardsToken in case of an active convexBooster.
 */
contract ConvexAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The poolId inside Convex booster for relevant Curve lpToken.
    uint256 public pid;

    /// @notice The booster address for Convex
    IConvexBooster public convexBooster;

    /// @notice The Convex convexRewards.
    IConvexRewards public convexRewards;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error AssetMismatch();

    /**
     * @notice Initialize a new Convex Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry The Convex Booster contract
     * @param convexInitData Encoded data for the convex adapter initialization.
     * @dev `_pid` - The poolId for lpToken.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory convexInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        uint256 _pid = abi.decode(convexInitData, (uint256));

        convexBooster = IConvexBooster(registry);
        pid = _pid;

        (address _asset, , , address _convexRewards, , ) = convexBooster
            .poolInfo(pid);

        if (_asset != asset()) revert AssetMismatch();

        convexRewards = IConvexRewards(_convexRewards);

        _name = string.concat(
            "VaultCraft Convex ",
            IERC20Metadata(_asset).name(),
            " Adapter"
        );
        _symbol = string.concat("vcCvx-", IERC20Metadata(_asset).symbol());

        IERC20(_asset).approve(address(convexBooster), type(uint256).max);
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
        return convexRewards.balanceOf(address(this));
    }

    /// @notice The token rewarded from the convex reward contract
    function rewardTokens()
        external
        view
        override
        returns (address[] memory tokens)
    {
        uint256 len = convexRewards.extraRewardsLength();

        tokens = new address[](len + 1);
        tokens[0] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV

        for (uint256 i; i < len; i++) {
            tokens[i + 1] = convexRewards.extraRewards(i).rewardToken();
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into Convex convexBooster contract.
    function _protocolDeposit(uint256 amount, uint256) internal override {
        convexBooster.deposit(pid, amount, true);
    }

    /// @notice Withdraw from Convex convexRewards contract.
    function _protocolWithdraw(uint256 amount, uint256) internal override {
        /**
         * @dev No need to convert as Convex shares are 1:1 with Curve deposits.
         * @param amount Amount of shares to withdraw.
         * @param claim Claim rewards on withdraw?
         */
        convexRewards.withdrawAndUnwrap(amount, false);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim liquidity mining rewards given that it's active
    function claim() public override onlyStrategy returns (bool success) {
        try convexRewards.getReward(address(this), true) {
            success = true;
        } catch {}
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
