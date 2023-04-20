// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../../abstracts/WithRewards.sol";
import {ICToken, IComptroller} from "./ICompoundV2.sol";
import {LibCompound} from "./LibCompound.sol";

/**
 * @title   CompoundV2 Adapter
 * @author  amatureApe
 * @notice  ERC4626 wrapper for CompoundV2 Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/beefyfinance/beefy-contracts/blob/master/contracts/BIFI/vaults/BeefyVaultV6.sol.
 * Allows wrapping CompoundV2 Vaults with or without an active Booster.
 * Allows for additional strategies to use rewardsToken in case of an active Booster.
 */
contract CompoundV2Adapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The Compound cToken contract
    ICToken public cToken;

    /// @notice The Compound Comptroller contract
    IComptroller public comptroller;

    /// @notice Check to see if cToken is cETH to wrap/unwarp on deposit/withdrawal
    bool public isCETH;

    // TODO allow user to deposit into cETH
    // - Dont allow native. Use wEth
    // - unwrap it?
    // - deposit?

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error DifferentAssets(address asset, address underlying);
    error InvalidAsset(address asset);

    /**
     * @notice Initialize a new CompoundV2 Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param comptroller_ The Compound comptroller.
     * @param compoundV2InitData Encoded data for the beefy adapter initialization.
     * @dev `_cToken` - The underlying asset supplied to and wrapped by Compound.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address comptroller_,
        bytes memory compoundV2InitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        _name = string.concat(
            "VaultCraft CompoundV2 ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcCv2-", IERC20Metadata(asset()).symbol());

        cToken = ICToken(abi.decode(compoundV2InitData, (address)));
        if (
            keccak256(abi.encode(cToken.symbol())) !=
            keccak256(abi.encode("cETH"))
        ) {
            if (cToken.underlying() != asset())
                revert DifferentAssets(cToken.underlying(), asset());
        }

        comptroller = IComptroller(comptroller_);

        (bool isListed, , ) = comptroller.markets(address(cToken));
        if (isListed == false) revert InvalidAsset(address(cToken));

        IERC20(asset()).approve(address(cToken), type(uint256).max);
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
        return _viewUnderlyingBalanceOf(address(cToken), address(this));
    }

    function _viewUnderlyingBalanceOf(
        address token,
        address user
    ) internal view returns (uint256) {
        ICToken token = ICToken(token);
        return LibCompound.viewUnderlyingBalanceOf(token, user);
    }

    /// @notice The amount of compound shares to withdraw given an mount of adapter shares
    function convertToUnderlyingShares(
        uint256 assets,
        uint256 shares
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    cToken.balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
    }

    /// @notice The token rewarded if compound liquidity mining is active
    function rewardTokens()
        external
        view
        override
        returns (address[] memory _rewardTokens)
    {
        _rewardTokens = new address[](1);
        _rewardTokens[0] = comptroller.getCompAddress();
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into compound cToken contract
    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        cToken.mint(amount);
    }

    /// @notice Withdraw from compound cToken contract
    function _protocolWithdraw(
        uint256,
        uint256 shares
    ) internal virtual override {
        uint256 compoundShares = convertToUnderlyingShares(0, shares);
        cToken.redeem(compoundShares);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim additional rewards given that it's active.
    function claim() public override onlyStrategy returns (bool success) {
        try comptroller.claimComp(address(this)) {
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
