// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {IDotDotStaking} from "./IDotDot.sol";

/**
 * @title   DotDot Adapter
 * @author  0xSolDev
 * @notice  ERC4626 wrapper for DotDot Vaults.
 *
 * An ERC4626 compliant Wrapper for https://dotdot.finance/#/stake.
 * Allows wrapping DotDot Vaults with or without an active Booster.
 * Allows for additional strategies to use rewardsToken in case of an active Booster.
 */
contract DotDotAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IDotDotStaking public lpStaking;

    error InvalidToken();

    /**
     * @notice Initialize a new DotDot Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry Endorsement Registry to check if the beefy adapter is endorsed.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        lpStaking = IDotDotStaking(registry);

        if (lpStaking.depositTokens(asset()) == address(0))
            revert InvalidToken();

        _name = string.concat(
            "Vaultcraft DotDot ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcDDD-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).approve(address(lpStaking), type(uint256).max);
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

    function _totalAssets() internal view override returns (uint256) {
        return lpStaking.userBalances(address(this), asset());
    }

    /// @notice The token rewarded if a beefy booster is configured
    function rewardTokens()
        external
        view
        override
        returns (address[] memory _rewardTokens)
    {
        uint256 extraRewardsLength = lpStaking.extraRewardsLength(asset());
        uint256 nRewardTokens = extraRewardsLength + 2;

        _rewardTokens = new address[](nRewardTokens);
        _rewardTokens[0] = lpStaking.EPX();
        _rewardTokens[1] = lpStaking.DDD();

        for (uint256 i; i < extraRewardsLength; i++) {
            _rewardTokens[i + 2] = lpStaking.extraRewards(asset(), i);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into dotdot vault and optionally into the booster given its configured
    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        lpStaking.deposit(address(this), asset(), amount);
    }

    /// @notice Withdraw from the dotdot vault and optionally from the booster given its configured
    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal virtual override {
        lpStaking.withdraw(address(this), asset(), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim rewards from the lpStaking given its configured
    function claim() public override onlyStrategy returns (bool success) {
        address[] memory tokens = new address[](1);
        tokens[0] = asset();
        try lpStaking.claim(address(this), tokens, 0) {
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
