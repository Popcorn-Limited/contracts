// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {IGauge, ILpToken} from "./IVelodrome.sol";
import {IPermissionRegistry} from "../../../../interfaces/vault/IPermissionRegistry.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract VelodromeAdapter is BaseAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;


    //// @notice The Velodrome contract
    IGauge public gauge;

    error InvalidAsset();
    error AssetMismatch();
    error LpTokenSupported();
    error NotEndorsed(address gauge);

    function __ConvexAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        if(!_adapterConfig.useLpToken) revert LpTokenSupported();
        __BaseAdapter_init(_adapterConfig);

        address _gauge = abi.decode(_protocolConfig.protocolInitData, (address));
        if (!IPermissionRegistry(_protocolConfig.registry).endorsed(_gauge))
            revert NotEndorsed(_gauge);

        gauge = IGauge(_gauge);
        if (gauge.stake() != address (lpToken)) revert InvalidAsset();

        _adapterConfig.lpToken.approve(address (_gauge), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of lptoken assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert
     * lpToken balance into lpToken balance
     */
    function _totalLP() internal view override returns (uint256) {
        return gauge.balanceOf(address(this));
    }



    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount) internal override {
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        _depositLP(amount);
    }

    /**
     * @notice Deposits lpToken asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overridden. Some farms require the user to into an lpToken before
     * depositing others might use the lpToken directly
     **/
    function _depositLP(uint256 amount) internal override {
        gauge.deposit(amount, 0);
    }


    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/
    function _withdraw(uint256 amount, address receiver) internal override {
        _withdrawLP(amount);
        underlying.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws lpToken asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overridden. Some farms require the user to into an lpToken before depositing others
     * might use the underlying directly
     **/
    function _withdrawLP(uint256 amount) internal override {
        gauge.withdraw(amount);
    }


    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function claim() public returns (bool success) {
        try gauge.getReward(address(this), _getRewardTokens()) {
            success = true;
        } catch {}
    }

    /**
    * @notice Gets all the reward tokens for a protocol
     * @dev This function converts all reward token types from IERC20[] to address[]
     **/
    function _getRewardTokens() internal virtual view returns(address[] memory) {
        uint256 len = rewardTokens.length;
        address[] memory _rewardTokens = new address[](len);
        for(uint256 i = 0; i < len ;) {
            _rewardTokens[i] = address(rewardTokens[i]);
            unchecked {
                i++;
            }
        }

        return _rewardTokens;
    }
}
