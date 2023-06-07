// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {IPermissionRegistry} from "../../../interfaces/vault/IPermissionRegistry.sol";
import {IGauge, IMinter, IController} from "./IBalancer.sol";

contract BalancerGaugeAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IMinter public balMinter;
    IGauge public gauge;
    address[] internal _rewardToken;

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
        address _gauge = abi.decode(balancerInitData, (address));

        // address controller = IMinter(registry).getGaugeController();
        // if (!IController(controller).gauge_exists(_gauge)) revert Disabled();

        // if (IGauge(_gauge).is_killed()) revert Disabled();

        balMinter = IMinter(registry);
        gauge = IGauge(_gauge);

        _rewardToken.push(IMinter(balMinter).getBalancerToken());

        __AdapterBase_init(adapterInitData);

        IERC20(asset()).approve(_gauge, type(uint256).max);

        _name = string.concat(
            "VaultCraft Balancer ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcBal-", IERC20Metadata(asset()).symbol());
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
        gauge.deposit(amount, address(this), false);
    }

    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal virtual override {
        gauge.withdraw(amount, false);
    }

    function claim() public override onlyStrategy returns (bool success) {
        try balMinter.mint(address(gauge)) {
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
