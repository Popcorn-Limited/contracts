// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../../../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../../../abstracts/WithRewards.sol";
import {IGauge, IGaugeFactory} from "../../ICurve.sol";

/**
 * @title   Curve Child Gauge Adapter
 * @notice  ERC4626 wrapper for  Curve Child Gauge Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/curvefi/curve-xchain-factory/blob/master/contracts/implementations/ChildGauge.vy.
 * Allows wrapping Curve Child Gauge Vaults.
 */
contract CurveChildGaugeAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The Curve Gauge contract
    IGauge public gauge;

    /// @notice The Curve Gauge contract
    IGaugeFactory public gaugeFactory;

    /// @notice The address of CRV
    address public crv;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    /**
     * @notice Initialize a new MasterChef Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev `_crv` - The CRV token.
     * @dev `_gauge` - The gauge contract for asset token.
     * @dev '_gaugeFactory' - The gauge factory.
     * @dev This function is called by the factory contract when deploying a new vault.
     */

    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory curveInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        address _crv = abi.decode(curveInitData, (address));

        crv = _crv;
        gaugeFactory = IGaugeFactory(registry);
        gauge = IGauge(gaugeFactory.get_gauge_from_lp_token(asset()));

        if (gauge.lp_token() != asset()) revert InvalidAsset();

        _name = string.concat(
            "VaultCraft CurveGauge ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcCrvG-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).approve(address(gauge), type(uint256).max);
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
        return gauge.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 amount, uint256) internal override {
        gauge.deposit(amount);
    }

    function _protocolWithdraw(uint256 amount, uint256) internal override {
        gauge.withdraw(amount);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Claim rewards from the masterChef
    function claim() public override onlyStrategy returns (bool success) {
        try gaugeFactory.mint(address(gauge)) {
            success = true;
        } catch {}
    }

    /// @notice The token rewarded
    function rewardTokens() external view override returns (address[] memory) {
        uint256 rewardCount = gauge.reward_count();
        address[] memory _rewardTokens = new address[](rewardCount + 1);
        _rewardTokens[0] = crv;
        for (uint256 i; i < rewardCount; ++i) {
            _rewardTokens[i + 1] = gauge.reward_tokens(i);
        }
        return _rewardTokens;
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
