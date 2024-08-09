// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurveGauge} from "src/interfaces/external/curve/ICurveGauge.sol";

struct WithdrawalRequest {
    address vault;
    uint256 burnAmount;
    uint256 minOut;
    address receiver;
}

/**
 * @title   VaultRouter
 * @author  RedVeil
 * @notice
 */
contract VaultRouter {
    using SafeERC20 for IERC20;

    error SlippageTooHigh();

    constructor() {}

    /*//////////////////////////////////////////////////////////////
                    SYNCHRONOUS INTERACTION LOGIC
    //////////////////////////////////////////////////////////////*/

    function depositAndStake(
        address vault,
        address gauge,
        uint256 assetAmount,
        uint256 minOut,
        address receiver
    ) external {
        IERC20 asset = IERC20(IERC4626(vault).asset());
        asset.safeTransferFrom(msg.sender, address(this), assetAmount);
        asset.approve(address(vault), assetAmount);

        uint256 shares = IERC4626(vault).deposit(assetAmount, address(this));

        if (shares < minOut) revert SlippageTooHigh();

        IERC4626(vault).approve(gauge, shares);
        ICurveGauge(gauge).deposit(shares, receiver);
    }

    function unstakeAndWithdraw(
        address vault,
        address gauge,
        uint256 burnAmount,
        uint256 minOut,
        address receiver
    ) external {
        IERC20(gauge).safeTransferFrom(msg.sender, address(this), burnAmount);

        ICurveGauge(gauge).withdraw(burnAmount);

        uint256 assets = IERC4626(vault).redeem(
            burnAmount,
            receiver,
            address(this)
        );

        if (assets < minOut) revert SlippageTooHigh();
    }

    /*//////////////////////////////////////////////////////////////
                      ASYNCHRONOUS INTERACTION LOGIC
    //////////////////////////////////////////////////////////////*/

    event RequestedWithdrawal(
        address indexed user,
        address indexed vault,
        address receiver,
        uint256 burnAmount,
        uint256 minOut,
        bytes32 requestId
    );

    event WithdrawalFullfilled(address indexed user, bytes32 requestId);

    mapping(bytes32 => WithdrawalRequest) public IdToRequest;
    bytes32[] public requestIds;

    function getRequestIds() external view returns (bytes32[] memory) {
        return requestIds;
    }

    function unstakeAndRequestWithdrawal(
        address vault,
        address gauge,
        uint256 burnAmount,
        uint256 minOut,
        address receiver
    ) external {
        IERC20(gauge).safeTransferFrom(msg.sender, address(this), burnAmount);

        ICurveGauge(gauge).withdraw(burnAmount);

        _requestWithdrawal(vault, burnAmount, minOut, receiver);
    }

    function requestWithdrawal(
        address vault,
        uint256 burnAmount,
        uint256 minOut,
        address receiver
    ) external {
        IERC20(vault).safeTransferFrom(msg.sender, address(this), burnAmount);
        _requestWithdrawal(vault, burnAmount, minOut, receiver);
    }

    function _requestWithdrawal(
        address vault,
        uint256 burnAmount,
        uint256 minOut,
        address receiver
    ) internal {
        bytes32 requestId = keccak256(
            abi.encodePacked(
                vault,
                burnAmount,
                minOut,
                receiver,
                msg.sender,
                block.timestamp
            )
        );
        IdToRequest[requestId] = WithdrawalRequest({
            vault: vault,
            burnAmount: burnAmount,
            minOut: minOut,
            receiver: receiver
        });
        requestIds.push(requestId);

        emit RequestedWithdrawal(
            msg.sender,
            vault,
            receiver,
            burnAmount,
            minOut,
            requestId
        );
    }

    function fullfillWithdrawal(bytes32 requestId) external {
        WithdrawalRequest memory request = IdToRequest[requestId];

        IERC20 asset = IERC20(IERC4626(request.vault).asset());

        _fullfillWithdrawal(requestId, request, asset);
    }

    function fullfillWithdrawals(bytes32[] memory requestIds) external {
        WithdrawalRequest memory request;
        uint256 len = requestIds.length;
        for (uint256 i; i < len; i++) {
            request = IdToRequest[requestIds[i]];

            _fullfillWithdrawal(
                requestIds[i],
                request,
                IERC20(IERC4626(request.vault).asset())
            );
        }
    }

    function _fullfillWithdrawal(
        bytes32 requestId,
        WithdrawalRequest memory request,
        IERC20 asset
    ) internal {
        asset.safeTransferFrom(msg.sender, request.receiver, request.minOut);

        IERC20(request.vault).transfer(msg.sender, request.burnAmount);

        emit WithdrawalFullfilled(msg.sender, requestId);
    }
}
