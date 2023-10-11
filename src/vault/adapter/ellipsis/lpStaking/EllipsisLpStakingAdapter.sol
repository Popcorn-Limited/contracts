// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../../abstracts/WithRewards.sol";
import {IEllipsis, ILpStaking, IAddressProvider} from "../IEllipsis.sol";

contract EllipsisLpStakingAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    ILpStaking public lpStaking;
    address[] internal _rewardToken;

    error InvalidToken();

    /**
     * @notice Initialize a new Ellipsis Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry Endorsement Registry to check if the ellipsis adapter is endorsed.
     * @param ellipsisInitData Encoded data for the ellipsis adapter initialization.
     * @dev `pid` - pool id of the lp token
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory ellipsisInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);
        uint256 pId = abi.decode(ellipsisInitData, (uint256));

        lpStaking = ILpStaking(registry);

        if (lpStaking.registeredTokens(pId) != asset()) revert InvalidToken();

        _rewardToken.push(lpStaking.rewardToken());

        _name = string.concat(
            "Vaultcraft Ellipsis ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcE-", IERC20Metadata(asset()).symbol());

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
        return lpStaking.userInfo(asset(), address(this)).depositAmount;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        lpStaking.deposit(asset(), amount, false);
    }

    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal virtual override {
        lpStaking.withdraw(asset(), amount, false);
    }

    function claim() public override onlyStrategy returns (bool success) {
        try lpStaking.claim(address(this), _rewardToken) {
            success = true;
        } catch {}
    }

    /// @notice The token rewarded
    function rewardTokens() external view override returns (address[] memory) {
        return _rewardToken;
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
