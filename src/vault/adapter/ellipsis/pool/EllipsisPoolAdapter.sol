// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter } from "../../abstracts/AdapterBase.sol";
import { WithRewards, IWithRewards } from "../../abstracts/WithRewards.sol";
import { IPermissionRegistry } from "../../../../interfaces/vault/IPermissionRegistry.sol";
import { IEllipsis, ILpStaking, IAddressProvider } from "../IEllipsis.sol";

contract EllipsisAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    address public ellipsisPool;
    address public ellipsisLPStaking;
    address public addressProvider;
    address public lpToken;

    error NotEndorsed(address _ellipsisPool);
    error InvalidToken();

    /**
    * @notice Initialize a new Ellipsis Adapter.
    * @param adapterInitData Encoded data for the base adapter initialization.
    * @param registry Endorsement Registry to check if the ellipsis adapter is endorsed.
    * @param ellipsisInitData Encoded data for the ellipsis adapter initialization.
    * @dev `ellipsisPool` - the address of Ellipsis Pool.
    * @dev `ellipsisLPStaking` - the address of LP staking contract.
    * @dev This function is called by the factory contract when deploying a new vault.
    */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory ellipsisInitData
    ) external initializer {
        (address _ellipsisPool, address _addressProvider, address _ellipsisLPStaking) = abi.decode(ellipsisInitData, (address,address,address));
        __AdapterBase_init(adapterInitData);

        if (!IPermissionRegistry(registry).endorsed(_ellipsisPool)) revert NotEndorsed(_ellipsisPool);
        if (!IPermissionRegistry(registry).endorsed(_addressProvider)) revert NotEndorsed(_addressProvider);
        if (!IPermissionRegistry(registry).endorsed(_ellipsisLPStaking)) revert NotEndorsed(_ellipsisLPStaking);

        _name = string.concat("VaultCraft Ellipsis", IERC20Metadata(asset()).name(), " Adapter");
        _symbol = string.concat("vcE-", IERC20Metadata(asset()).symbol());

        ellipsisPool = _ellipsisPool;
        addressProvider = _addressProvider;
        ellipsisLPStaking = _ellipsisLPStaking;
        lpToken = IAddressProvider(_addressProvider).get_lp_token(_ellipsisPool);

        IERC20(asset()).approve(_ellipsisPool, type(uint256).max);
        IERC20(lpToken).approve(_ellipsisLPStaking, type(uint256).max);
    }

    function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _name;
    }

    function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function _totalAssets() internal view override returns (uint256) {

        uint256 lpBalance = ILpStaking(ellipsisLPStaking).userInfo(lpToken, address(this)).depositAmount;

        if (lpBalance > 0) {
            uint256 n_coins = IAddressProvider(addressProvider).get_n_coins(ellipsisPool);

            address[4] memory coins = IAddressProvider(addressProvider).get_coins(ellipsisPool);
            for (uint256 i = 0; i < n_coins; i++) {
                if (coins[i] == asset()) {
                    return IEllipsis(ellipsisPool).calc_withdraw_one_coin(lpBalance, int128(uint128(i)));
                }
            }
        }
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice The amount of ellipsis shares to withdraw given an amount of adapter shares
    function convertToUnderlyingShares(uint256, uint256 shares) public view override returns (uint256) {

        uint256 lpBalance = ILpStaking(ellipsisLPStaking).userInfo(lpToken, address(this)).depositAmount;

        uint256 supply = totalSupply();
        return supply == 0 ? shares : shares.mulDiv(lpBalance, supply, Math.Rounding.Up);
        
    }

    function _protocolDeposit(uint256 amount, uint256)
        internal
        virtual
        override
    {
        if (address(ellipsisLPStaking) != address(0)) {
            uint256 n_coins = IAddressProvider(addressProvider).get_n_coins(ellipsisPool);
            address[4] memory coins = IAddressProvider(addressProvider).get_coins(ellipsisPool);
            if (n_coins == 2) {
                uint256[2] memory amounts;
                for (uint i = 0; i < n_coins; i++) {
                    if (coins[i] == asset()) {
                        amounts[i] = amount;
                    }
                }
                IEllipsis(ellipsisPool).add_liquidity(amounts, 0);
            } else if (n_coins == 3) {
                uint256[3] memory amounts;
                for (uint i = 0; i < n_coins; i++) {
                    if (coins[i] == asset()) {
                        amounts[i] = amount;
                    } else {
                        amounts[i] = 0;
                    }
                }
                IEllipsis(ellipsisPool).add_liquidity(amounts, 0);
            } else {
                uint256[4] memory amounts;
                for (uint i = 0; i < n_coins; i++) {
                    if (coins[i] == asset()) {
                        amounts[i] = amount;
                    }
                }
                IEllipsis(ellipsisPool).add_liquidity(amounts, 0);
            }
            uint256 lpTokenBalance = IERC20(lpToken).balanceOf(address(this));
            
            ILpStaking(ellipsisLPStaking).deposit(lpToken, lpTokenBalance, false);
        }
    }

    function _protocolWithdraw(uint256, uint256 share)
        internal
        virtual
        override
    {
        uint256 _lpShare = convertToUnderlyingShares(0, share);
        ILpStaking(ellipsisLPStaking).withdraw(lpToken, _lpShare, false);
        uint256 n_coins = IAddressProvider(addressProvider).get_n_coins(ellipsisPool);

        uint256 lpTokenBalance = IERC20(lpToken).balanceOf(address(this));

        address[4] memory coins = IAddressProvider(addressProvider).get_coins(ellipsisPool);
        for (uint256 i = 0; i < n_coins; i++) {
            if (coins[i] == asset()) {
                IEllipsis(ellipsisPool).remove_liquidity_one_coin(lpTokenBalance, int128(uint128(i)), 0);
                break;
            }
        }
    }

    function claim() public override onlyStrategy returns (bool success) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = ILpStaking(ellipsisLPStaking).rewardToken();
        try 
        ILpStaking(ellipsisLPStaking).claim(address(this), _rewardTokens) {
            success = true;
        } catch {}
    }

    /// @notice The token rewarded
    function rewardTokens() external view override returns (address[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = ILpStaking(ellipsisLPStaking).rewardToken();
        return _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                      EIP-165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId)
        public
        pure
        override(WithRewards, AdapterBase)
        returns (bool)
    {
        return
            interfaceId == type(IWithRewards).interfaceId ||
            interfaceId == type(IAdapter).interfaceId;
    }
}