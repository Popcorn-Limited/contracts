// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {IAuraBooster, IAuraRewards, IAuraStaking} from "./IAura.sol";
import {IBalancerVault, SwapKind, IAsset, BatchSwapStep, FundManagement, JoinPoolRequest} from "../../../interfaces/external/balancer/IBalancerVault.sol";

/**
 * @title  Aura Adapter
 * @author amatureApe
 * @notice ERC4626 wrapper for Aura Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/sushiswap/sushiswap/blob/archieve/canary/contracts/Aura.sol.
 * Allows wrapping Aura Vaults.
 */
contract AuraCompounder is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The Aura booster contract
    IAuraBooster public auraBooster;

    /// @notice The reward contract for Aura gauge
    IAuraRewards public auraRewards;

    /// @notice The pool ID
    uint256 public pid;

    address internal balVault;
    bytes32 internal balPoolId;

    address public crv;
    address public cvx;
    address public weth;
    address[] internal _rewardToken;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    /**
     * @notice Initialize a new Aura Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry `_auraBooster` - The main Aura contract
     * @param auraInitData aura specific init data
     * @dev `_pid` - The poolId for lpToken.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory auraInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        (uint256 _pid, address _balVault, bytes32 _balPoolId, address _weth) = abi.decode(
            auraInitData,
            (uint256, address, bytes32, address)
        );

        auraBooster = IAuraBooster(registry);
        pid = _pid;
        balVault = _balVault;
        balPoolId = _balPoolId;
        weth = _weth;

        IAuraStaking auraStaking = IAuraStaking(auraBooster.stakerRewards());
        crv = auraStaking.crv();
        _rewardToken.push(crv);
        cvx = auraStaking.cvx();
        _rewardToken.push(cvx);

        (address balancerLpToken, , , address _auraRewards, , ) = auraBooster
            .poolInfo(pid);

        auraRewards = IAuraRewards(_auraRewards);

        if (balancerLpToken != asset()) revert InvalidAsset();

        _name = string.concat(
            "VaultCraft Aura ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcAu-", IERC20Metadata(asset()).symbol());

        IERC20(balancerLpToken).approve(
            address(auraBooster),
            type(uint256).max
        );
         IERC20(crv).approve(
            _balVault,
            type(uint256).max
        );
         IERC20(cvx).approve(
            _balVault,
            type(uint256).max
        );
         IERC20(_weth).approve(
            _balVault,
            type(uint256).max
        );
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
        return auraRewards.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 amount, uint256) internal override {
        auraBooster.deposit(pid, amount, true);
    }

    function _protocolWithdraw(uint256 amount, uint256) internal override {
        auraRewards.withdrawAndUnwrap(amount, true);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim rewards from the aura
    function claim() public override returns (bool success) {
        try auraRewards.getReward() {
            success = true;
        } catch {}
    }

    /// @notice The token rewarded
    function rewardTokens() external view override returns (address[] memory) {
        return _rewardToken;
    }

    /**
     * @notice Execute Strategy and take fees.
     * @dev Delegatecall to strategy's harvest() function. All necessary data is passed via `strategyConfig`.
     * @dev Delegatecall is used to in case any logic requires the adapters address as a msg.sender. (e.g. Synthetix staking)
     */
    function harvest() public override takeFees {
        if ((lastHarvest + harvestCooldown) < block.timestamp) {
            claim();

            // Trade to base asset
            uint256 len = _rewardToken.length;
            for (uint256 i = 0; i < len; i++) {
                uint256 rewardBal = IERC20(_rewardToken[i]).balanceOf(
                    address(this)
                );
                if (rewardBal >= minTradeAmounts[i]) {
                    swaps[_rewardToken[i]][0].amount = rewardBal;
                    IBalancerVault(balVault).batchSwap(
                        SwapKind.GIVEN_IN,
                        swaps[_rewardToken[i]],
                        assets[_rewardToken[i]],
                        FundManagement(
                            address(this),
                            false,
                            payable(address(this)),
                            false
                        ),
                        limits[_rewardToken[i]],
                        block.timestamp
                    );
                }
            }
            uint256 poolAmount = baseAsset.balanceOf(address(this));
            if (poolAmount > 0) {
                uint256[] memory amounts = new uint256[](underlyings.length);
                amounts[indexIn] = poolAmount;

                bytes memory userData;
                if (underlyings.length != amountsInLen) {
                    uint256[] memory amountsIn = new uint256[](amountsInLen);
                    amountsIn[indexIn] = poolAmount;
                    userData = abi.encode(1, amountsIn, 0); // Exact In Enum, inAmounts, minOut
                } else {
                    userData = abi.encode(1, amounts, 0); // Exact In Enum, inAmounts, minOut
                }

                // Pool base asset
                IBalancerVault(balVault).joinPool(
                    balPoolId,
                    address(this),
                    address(this),
                    JoinPoolRequest(underlyings, amounts, userData, false)
                );

                // redeposit
                _protocolDeposit(IERC20(asset()).balanceOf(address(this)), 0);

                lastHarvest = block.timestamp;
            }
        }

        emit Harvested();
    }

    mapping(address => BatchSwapStep[]) swaps;
    mapping(address => IAsset[]) assets;
    mapping(address => int256[]) limits;
    uint256[] internal minTradeAmounts;
    IERC20 internal baseAsset;
    address[] internal underlyings;
    uint256 internal indexIn;
    uint256 internal amountsInLen;

    function setHarvestValues(
        BatchSwapStep[][2] memory swaps_,
        IAsset[][2] memory assets_,
        int256[][2] memory limits_,
        uint256[] memory minTradeAmounts_,
        IERC20 baseAsset_,
        address[] memory underlyings_,
        uint256 indexIn_,
        uint256 amountsInLen_
    ) external onlyOwner {
        _setTradeData(crv, swaps_[0], assets_[0], limits_[0]);
        _setTradeData(cvx, swaps_[1], assets_[1], limits_[1]);

        minTradeAmounts = minTradeAmounts_;
        baseAsset = baseAsset_;
        underlyings = underlyings_;
        indexIn = indexIn_;
        amountsInLen = amountsInLen_;
    }

    function _setTradeData(
        address key,
        BatchSwapStep[] memory swaps_,
        IAsset[] memory assets_,
        int256[] memory limits_
    ) internal {
        uint256 storageLen = swaps[key].length;
        uint256 len = swaps_.length;
        for (uint256 i; i < len; i++) {
            if (i >= storageLen) {
                swaps[key].push(swaps_[i]);
            } else {
                swaps[key][i] = swaps_[i];
            }
        }
        limits[key] = limits_;
        assets[key] = assets_;
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
