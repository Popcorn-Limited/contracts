// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {IERC4626, IERC20, IERC20Metadata} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC4626Upgradeable, ERC20Upgradeable as ERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {Pausable} from "src/utils/Pausable.sol";
import {IERC7540Redeem} from "ERC-7540/interfaces/IERC7540.sol";

contract MockERC7540 is ERC4626Upgradeable, IERC7540Redeem, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public beforeWithdrawHookCalledCounter = 0;
    uint256 public afterDepositHookCalledCounter = 0;

    uint8 internal _decimals;
    uint8 public constant decimalOffset = 0;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    function initialize(
        IERC20 _asset,
        string memory,
        string memory
    ) external initializer {
        __ERC4626_init(IERC20Metadata(address(_asset)));
        _decimals = IERC20Metadata(address(_asset)).decimals() + decimalOffset;
    }

    /*//////////////////////////////////////////////////////////////
                            GENERAL VIEWS
    //////////////////////////////////////////////////////////////*/

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view override returns (uint256 shares) {
        return
            assets.mulDiv(
                totalSupply() + 10 ** decimalOffset,
                totalAssets() + 1,
                rounding
            );
    }

    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view override returns (uint256) {
        return
            shares.mulDiv(
                totalAssets() + 1,
                totalSupply() + 10 ** decimalOffset,
                rounding
            );
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);
        _mint(receiver, shares);

        afterDepositHookCalledCounter++;

        emit Deposit(caller, receiver, assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = convertToShares(assets);

        _burn(address(this), shares);

        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                        ASYNC WITHDRAW MOCK LOGIC
    //////////////////////////////////////////////////////////////*/

    mapping (address => uint256) public requestedShares; 
    mapping (address => uint256) public claimableAssets; 

    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) external returns (uint256 requestId) {
        requestedShares[controller] += shares;

        // Transfer shares from owner to vault (these will be burned on withdrawal)
        IERC20(address(this)).safeTransferFrom(owner, address(this), shares);
    }

    function fulfillRedeem(
        uint256 shares,
        address controller
    ) external returns (uint256) {
        uint256 assets = convertToAssets(shares);
        claimableAssets[controller] = assets;

        return assets;
    }

    function cancelRedeemRequest(address controller) external {
        uint256 shares = requestedShares[controller];
        requestedShares[controller] = 0;

         // Transfer the pending shares back to the receiver
        IERC20(address(this)).safeTransfer(controller, shares);
    }

    function pendingRedeemRequest(uint256 requestId, address controller)
    external
    view
    returns (uint256 pendingShares) {
        pendingShares = requestedShares[controller];
    }

    function claimableRedeemRequest(uint256 requestId, address controller)
    external
    view
    returns (uint256 claimableShares) {
        claimableShares = convertToShares(claimableAssets[controller]);
    }

    /*//////////////////////////////////////////////////////////////
                          PAUSABLE LOGIC
    //////////////////////////////////////////////////////////////*/

    function pause() public override {
        _pause();
    }

    function unpause() public override {
        _unpause();
    }
}