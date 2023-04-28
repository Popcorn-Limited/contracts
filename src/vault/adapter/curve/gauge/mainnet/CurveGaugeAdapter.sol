// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../../../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../../../abstracts/WithRewards.sol";
import {IGauge, IMinter, IGaugeController} from "../../ICurve.sol";

/**
 * @title   Curve Gauge Adapter
 * @notice  ERC4626 wrapper for  Curve Gauge Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/curvefi/curve-xchain-factory/blob/master/contracts/ChildGaugeFactory.vy.
 * Allows wrapping Curve Gauge Vaults.
 */
contract CurveGaugeAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The Curve Gauge contract
    IGauge public gauge;

    /// @notice The Curve Gauge contract
    IMinter public minter;

    address public crv;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    /**
     * @notice Initialize a new MasterChef Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry The Curve Minter on mainnet
     * @param curveInitData Init data for the curve adapter
     * @dev `_gaugeId` - The index of the gauge of asset();
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory curveInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        uint256 _gaugeId = abi.decode(curveInitData, (uint256));

        minter = IMinter(registry);
        gauge = IGauge(IGaugeController(minter.controller()).gauges(_gaugeId));
        crv = minter.token();

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
        try minter.mint(address(gauge)) {
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
