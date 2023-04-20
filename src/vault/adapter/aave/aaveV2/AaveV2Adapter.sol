// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../../abstracts/WithRewards.sol";
import {ILendingPool, IAaveMining, IAToken, IProtocolDataProvider} from "./IAaveV2.sol";
import {DataTypes} from "./lib.sol";

/**
 * @title   AaveV2 Adapter
 * @author  amatureApe
 * @notice  ERC4626 wrapper for AaveV2 Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/aave/protocol-v2/blob/master/contracts/protocol/lendingpool/LendingPool.sol.
 * Allows wrapping AaveV2 aTokens with or without an active Liquidity Mining.
 * Allows for additional strategies to use rewardsToken in case of an active Liquidity Mining.
 */

contract AaveV2Adapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    // @notice The Aave aToken contract
    IAToken public aToken;

    // @notice The Aave liquidity mining contract
    IAaveMining public aaveMining;

    // @notice Check to see if Aave liquidity mining is active
    bool public isActiveMining;

    // @notice The Aave LendingPool contract
    ILendingPool public lendingPool;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant halfRAY = RAY / 2;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    error DifferentAssets(address asset, address underlying);

    /**
     * @notice Initialize a new AaveV2 Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param aaveDataProvider Encoded data for the base adapter initialization.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address aaveDataProvider,
        bytes memory
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        _name = string.concat(
            "VaultCraft AaveV2 ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcAv2-", IERC20Metadata(asset()).symbol());

        (address _aToken, , ) = IProtocolDataProvider(aaveDataProvider)
            .getReserveTokensAddresses(asset());
        aToken = IAToken(_aToken);
        if (aToken.UNDERLYING_ASSET_ADDRESS() != asset())
            revert DifferentAssets(aToken.UNDERLYING_ASSET_ADDRESS(), asset());

        lendingPool = ILendingPool(aToken.POOL());
        aaveMining = IAaveMining(aToken.getIncentivesController());

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
        return aToken.balanceOf(address(this));
    }

    /// @notice The token rewarded if the aave liquidity mining is active
    function rewardTokens()
        external
        view
        override
        returns (address[] memory _rewardTokens)
    {
        _rewardTokens = new address[](1);
        if (address(aaveMining) != address(0)) {
            _rewardTokens[0] = aaveMining.REWARD_TOKEN();
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
        if (address(aaveMining) == address(0)) return false;

        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        try aaveMining.claimRewards(assets, type(uint256).max, address(this)) {
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
