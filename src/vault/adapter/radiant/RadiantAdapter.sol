// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {ILendingPool, IRadiantMining, IRToken, IProtocolDataProvider} from "./IRadiant.sol";
import {DataTypes} from "./lib.sol";

/**
 * @title   Radiant Adapter
 * @author  amatureApe
 * @notice  ERC4626 wrapper for Radiant Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/aave/protocol-v2/blob/master/contracts/protocol/lendingpool/LendingPool.sol.
 * Allows wrapping Radiant aTokens with or without an active Liquidity Mining.
 * Allows for additional strategies to use rewardsToken in case of an active Liquidity Mining.
 */

contract RadiantAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The Radiant rToken contract
    IRToken public rToken;

    /// @notice The Radiant liquidity mining contract
    IRadiantMining public radiantMining;

    /// @notice Check to see if Radiant liquidity mining is active
    bool public isActiveMining;

    /// @notice The Radiant LendingPool contract
    ILendingPool public lendingPool;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant halfRAY = RAY / 2;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    error DifferentAssets(address asset, address underlying);

    /**
     * @notice Initialize a new Radiant Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param radiantDataProvider Encoded data for the base adapter initialization.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address radiantDataProvider,
        bytes memory
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        _name = string.concat(
            "VaultCraft Radiant ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcRdt-", IERC20Metadata(asset()).symbol());

        (address _rToken, , ) = IProtocolDataProvider(radiantDataProvider)
            .getReserveTokensAddresses(asset());
        rToken = IRToken(_rToken);
        if (rToken.UNDERLYING_ASSET_ADDRESS() != asset())
            revert DifferentAssets(rToken.UNDERLYING_ASSET_ADDRESS(), asset());

        lendingPool = ILendingPool(rToken.POOL());
        radiantMining = IRadiantMining(rToken.getIncentivesController());

        IERC20(asset()).approve(address(lendingPool), type(uint256).max);
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
        return rToken.balanceOf(address(this));
    }

    /// @notice The token rewarded if the aave liquidity mining is active
    function rewardTokens()
        external
        view
        override
        returns (address[] memory _rewardTokens)
    {
        _rewardTokens = new address[](1);
        if (address(radiantMining) != address(0)) {
            _rewardTokens[0] = radiantMining.REWARD_TOKEN();
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into aave lending pool
    function _protocolDeposit(
        uint256 assets,
        uint256
    ) internal virtual override {
        lendingPool.deposit(asset(), assets, address(this), 0);
    }

    /// @notice Withdraw from lending pool
    function _protocolWithdraw(
        uint256 assets,
        uint256
    ) internal virtual override {
        lendingPool.withdraw(asset(), assets, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim liquidity mining rewards given that it's active
    function claim() public override onlyStrategy returns (bool success) {
        if (address(radiantMining) == address(0)) return false;

        address[] memory assets = new address[](1);
        assets[0] = address(rToken);

        try
            radiantMining.claimRewards(assets, type(uint256).max, address(this))
        {
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
