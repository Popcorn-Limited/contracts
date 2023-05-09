// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {IConvexUSDCMultiFarm, ICurvePool, IConvexBooster, IConvexRewards, IRewards} from "./IConvexUSDCMultiFarm.sol";

/**
 * @title   ConvexUSDCMultiFarm Adapter
 * @author  amatureApe
 * @notice  ERC4626 wrapper for ConvexUSDCMultiFarm Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/convex-eth/platform/blob/main/contracts/contracts/Booster.sol.
 * Allows wrapping Convex Vaults.
 */
contract ConvexUSDCMultiFarmAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice Metavault strategy base
    IConvexUSDCMultiFarm public metavaultStrategy;

    /// @notice The booster address for Convex
    IConvexBooster public convexBooster;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error AssetMismatch();

    /**
     * @notice Initialize a new ConvexUSDCMultiFarmAdapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry The Convex Booster contract
     * @param convexInitData Encoded data for the convex adapter initialization.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory convexInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        metavaultStrategy = IConvexUSDCMultiFarm(address(strategy));

        convexBooster = IConvexBooster(registry);

        _name = string.concat(
            "VaultCraft Convex ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcCvx-", IERC20Metadata(asset()).symbol());

        uint256 len = metavaultStrategy.getProtocolUint(5).num;
        for (uint256 i; i < len; ++i) {
            address _curvePool = metavaultStrategy
                .getProtocolAddress(i + 6)
                .addr;
            ICurvePool curvePool = ICurvePool(_curvePool);

            IERC20(asset()).approve(address(curvePool), type(uint256).max);
            curvePool.approve(address(convexBooster), type(uint256).max);
        }
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
        uint256 total;

        uint256 len = metavaultStrategy.getProtocolUint(5).num;

        for (uint256 i; i < len; ++i) {
            uint256 _pid = metavaultStrategy.getProtocolUint(i + 5).num;
            (, , , address _convexRewards, , ) = convexBooster.poolInfo(_pid);

            IConvexRewards convexRewards = IConvexRewards(_convexRewards);

            total += convexRewards.balanceOf(address(this));
        }

        return total;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Add liquidity into Cure pool and then deposit into Convex convexBooster contract.
    function _protocolDeposit(uint256 amount, uint256) internal override {
        IConvexUSDCMultiFarm strategy = IConvexUSDCMultiFarm(address(strategy));
        uint256 len = strategy.getProtocolUint(5).num;

        uint256 depositAmount = amount / len;

        for (uint256 i; i < len; ++i) {
            address _curvePool = metavaultStrategy
                .getProtocolAddress(i + 6)
                .addr;
            ICurvePool curvePool = ICurvePool(_curvePool);
            uint256 pid = metavaultStrategy.getProtocolUint(i + 6).num;

            uint256[] memory tokens = curvePool.get_balances();
            uint256 tokensLen = tokens.length;

            uint256[] memory depositAmounts = new uint256[](tokensLen);

            for (uint256 j; j < tokensLen; ++j) {
                if (curvePool.coins(j) == address(asset())) {
                    depositAmounts[j] = depositAmount;
                } else {
                    depositAmounts[j] = 0;
                }
            }

            curvePool.add_liquidity(depositAmounts, 0);
            convexBooster.deposit(pid, depositAmount, true);
        }
    }

    /// @notice Withdraw from Convex convexRewards contract and then withdraw liquidity from Curve pool.
    function _protocolWithdraw(uint256 amount, uint256) internal override {
        uint256 len = metavaultStrategy.getProtocolUint(5).num;

        uint256 withdrawAmount = amount / len;

        for (uint256 i; i < len; ++i) {
            uint256 _pid = metavaultStrategy.getProtocolUint(i + 5).num;
            (, , , address _convexRewards, , ) = convexBooster.poolInfo(_pid);
            address _curvePool = metavaultStrategy
                .getProtocolAddress(i + 6)
                .addr;

            IConvexRewards convexRewards = IConvexRewards(_convexRewards);
            ICurvePool curvePool = ICurvePool(_curvePool);

            convexRewards.withdrawAndUnwrap(withdrawAmount, false);

            uint256[] memory tokens = curvePool.get_balances();
            uint256 tokensLen = tokens.length;

            int128 tokenIdx;

            for (uint256 j; j < tokensLen; ++j) {
                if (curvePool.coins(j) == address(asset())) {
                    tokenIdx = int256ToInt128(int256(j));
                }
            }

            curvePool.remove_liquidity_one_coin(withdrawAmount, tokenIdx, 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Claim liquidity mining rewards from Convex given that they are active.
    function claim() public override onlyStrategy returns (bool success) {
        uint256 len = metavaultStrategy.getProtocolUint(5).num;

        for (uint256 i; i < len; ++i) {
            uint256 _pid = metavaultStrategy.getProtocolUint(i + 5).num;
            (, , , address _convexRewards, , ) = convexBooster.poolInfo(_pid);

            IConvexRewards convexRewards = IConvexRewards(_convexRewards);

            try convexRewards.getReward(address(this), true) {
                success = true;
            } catch {}
        }
    }

    /// @notice View all reward tokens accumulated by strategy from Convex.
    function rewardTokens()
        external
        view
        override
        returns (address[] memory tokens)
    {
        uint256 len = metavaultStrategy.getProtocolUint(5).num;
        uint256 totalRewards;

        for (uint256 i; i < len; ++i) {
            uint256 _pid = metavaultStrategy.getProtocolUint(i + 5).num;
            (, , , address _convexRewards, , ) = convexBooster.poolInfo(_pid);

            IConvexRewards convexRewards = IConvexRewards(_convexRewards);

            totalRewards += convexRewards.extraRewardsLength();
        }

        tokens = new address[](totalRewards + 1);
        tokens[0] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV

        for (uint256 i; i < len; ++i) {
            uint256 _pid = metavaultStrategy.getProtocolUint(i + 5).num;
            (, , , address _convexRewards, , ) = convexBooster.poolInfo(_pid);

            IConvexRewards convexRewards = IConvexRewards(_convexRewards);

            uint256 rewardsLen = convexRewards.extraRewardsLength();

            for (uint256 j; j < rewardsLen; ++j) {
                uint256 currentIndex = i * rewardsLen + j + 1;

                tokens[currentIndex] = convexRewards
                    .extraRewards(j)
                    .rewardToken();
            }
        }
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

    // /*//////////////////////////////////////////////////////////////
    //                       UTILITY FUNCTIONS
    // //////////////////////////////////////////////////////////////*/

    error IntOutOfRange(int256 value);

    function int256ToInt128(int256 _value) public pure returns (int128) {
        if (_value > type(int128).max) revert IntOutOfRange(_value);

        return int128(_value);
    }
}
