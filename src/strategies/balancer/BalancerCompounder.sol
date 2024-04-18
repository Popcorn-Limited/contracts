// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../BaseStrategy.sol";
import {IBalancerVault, SwapKind, IAsset, BatchSwapStep, FundManagement, JoinPoolRequest} from "../../../interfaces/external/balancer/IBalancerVault.sol";
import {IMinter, IGauge} from "./IBalancer.sol";

struct HarvestValue {
    BatchSwapStep[] swaps;
    IAsset[] assets;
    int256[] limits;
    uint256 minTradeAmount;
    address baseAsset;
    address[] underlyings;
    uint256 indexIn;
    uint256 amountsInLen;
    bytes32 balPoolId;
}

/**
 * @title  Aura Adapter
 * @author amatureApe
 * @notice ERC4626 wrapper for Aura Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/sushiswap/sushiswap/blob/archieve/canary/contracts/Aura.sol.
 * Allows wrapping Aura Vaults.
 */
contract BalancerCompounder is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IMinter public balMinter;
    IBalancerVault public balVault;
    IGauge public gauge;

    address internal _rewardToken;
    address[] internal _rewardTokens;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();
    error Disabled();

    /**
     * @notice Initialize a new Balancer Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry Endorsement Registry to check if the balancer adapter is endorsed.
     * @param balancerInitData Encoded data for the balancer adapter initialization.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory balancerInitData
    ) external initializer {
        (address _gauge, address _balVault) = abi.decode(
            balancerInitData,
            (address, address)
        );

        if (IGauge(_gauge).is_killed()) revert Disabled();

        balMinter = IMinter(registry);
        balVault = IBalancerVault(_balVault);
        gauge = IGauge(_gauge);

        address rewardToken_ = balMinter.getBalancerToken();
        _rewardToken = rewardToken_;
        _rewardTokens.push(rewardToken_);

        __BaseStrategy_init(adapterInitData);

        IERC20(asset()).approve(_gauge, type(uint256).max);
        IERC20(_rewardToken).approve(_balVault, type(uint256).max);

        _name = string.concat(
            "VaultCraft BalancerCompounder ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-bc-", IERC20Metadata(asset()).symbol());
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
        return gauge.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        gauge.deposit(amount);
    }

    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal virtual override {
        gauge.withdraw(amount, false);
    }
    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    function claim() public override returns (bool success) {
        try balMinter.mint(address(gauge)) {
            success = true;
        } catch {}
    }

    /// @notice The token rewarded
    function rewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }
    /**
     * @notice Execute Strategy and take fees.
     * @dev Delegatecall to strategy's harvest() function. All necessary data is passed via `strategyConfig`.
     * @dev Delegatecall is used to in case any logic requires the adapters address as a msg.sender. (e.g. Synthetix staking)
     */
    function harvest() public override takeFees {
        if ((lastHarvest + harvestCooldown) < block.timestamp) {
            claim();

            HarvestValue memory harvestValue_ = harvestValue;

            // Trade to base asset
            uint256 rewardBal = IERC20(_rewardToken).balanceOf(address(this));
            if (rewardBal >= harvestValue_.minTradeAmount) {
                harvestValue_.swaps[0].amount = rewardBal;
                balVault.batchSwap(
                    SwapKind.GIVEN_IN,
                    harvestValue_.swaps,
                    harvestValue_.assets,
                    FundManagement(
                        address(this),
                        false,
                        payable(address(this)),
                        false
                    ),
                    harvestValue_.limits,
                    block.timestamp
                );
            }

            uint256 poolAmount = IERC20(harvestValue_.baseAsset).balanceOf(
                address(this)
            );
            if (poolAmount > 0) {
                uint256[] memory amounts = new uint256[](
                    harvestValue_.underlyings.length
                );
                amounts[harvestValue_.indexIn] = poolAmount;

                bytes memory userData;
                if (
                    harvestValue_.underlyings.length !=
                    harvestValue_.amountsInLen
                ) {
                    uint256[] memory amountsIn = new uint256[](
                        harvestValue_.amountsInLen
                    );
                    amountsIn[harvestValue_.indexIn] = poolAmount;
                    userData = abi.encode(1, amountsIn, 0); // Exact In Enum, inAmounts, minOut
                } else {
                    userData = abi.encode(1, amounts, 0); // Exact In Enum, inAmounts, minOut
                }

                // Pool base asset
                balVault.joinPool(
                    harvestValue_.balPoolId,
                    address(this),
                    address(this),
                    JoinPoolRequest(
                        harvestValue_.underlyings,
                        amounts,
                        userData,
                        false
                    )
                );

                // redeposit
                _protocolDeposit(IERC20(asset()).balanceOf(address(this)), 0);

                lastHarvest = block.timestamp;
            }
        }

        emit Harvested();
    }

    HarvestValue internal harvestValue;

    function setHarvestValues(
        HarvestValue calldata harvestValue_
    ) public onlyOwner {
        harvestValue = harvestValue_;
    }

   
}
