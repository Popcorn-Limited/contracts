// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { FeeRecipientProxy } from "../../src/vault/FeeRecipientProxy.sol";
import { MockERC20 } from "../utils/mocks/MockERC20.sol";
import { IERC20Upgradeable as IERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract FeeRecipientProxyTest is Test {
  FeeRecipientProxy feeRecipient;
  MockERC20 asset1;
  MockERC20 asset2;
  MockERC20 asset3;

  address owner = address(0x4444);

  IERC20[] tokens;

  event TokenApproved(uint8 len);
  event TokenApprovalVoided(uint8 len);

  function setUp() public {
    asset1 = new MockERC20("Mock Token", "TKN", 18);
    asset2 = new MockERC20("Mock Token", "TKN", 6);
    asset3 = new MockERC20("Mock Token", "TKN", 2);

    feeRecipient = new FeeRecipientProxy(owner);
  }

  // 2. Approve gifted token
  // 3. Owner pulls approved token
  // 4. Owner cant pull non-approved token
  // 5. void approval
  // 6. Approval change only works when all is voided

  /*//////////////////////////////////////////////////////////////
                              HELPER
    //////////////////////////////////////////////////////////////*/

  function giftToken(MockERC20 asset, uint256 amount) internal {
    asset.mint(address(feeRecipient), amount);
  }

  function approveToken(IERC20[] memory _tokens) internal {
    vm.prank(owner);
    feeRecipient.approveToken(_tokens);
  }

  /*//////////////////////////////////////////////////////////////
                          APPROVE TOKEN
    //////////////////////////////////////////////////////////////*/

  function test__approveToken() public {
    tokens.push(IERC20(address(asset1)));

    vm.prank(owner);
    vm.expectEmit(false, false, false, true, address(feeRecipient));
    emit TokenApproved(uint8(1));

    feeRecipient.approveToken(tokens);

    assertEq(asset1.allowance(address(feeRecipient), owner), type(uint256).max);
    assertEq(feeRecipient.approvals(), 1);

    tokens[0] = IERC20(address(asset2));
    tokens.push(IERC20(address(asset3)));

    vm.prank(owner);
    vm.expectEmit(false, false, false, true, address(feeRecipient));
    emit TokenApproved(uint8(2));

    feeRecipient.approveToken(tokens);

    assertEq(asset1.allowance(address(feeRecipient), owner), type(uint256).max);
    assertEq(asset2.allowance(address(feeRecipient), owner), type(uint256).max);
    assertEq(asset3.allowance(address(feeRecipient), owner), type(uint256).max);
    assertEq(feeRecipient.approvals(), 3);

    // Transfer approved token to owner
    giftToken(asset1, 1e18);

    vm.prank(owner);
    asset1.transferFrom(address(feeRecipient), owner, 1e18);

    assertEq(asset1.balanceOf(address(feeRecipient)), 0);
    assertEq(asset1.balanceOf(owner), 1e18);
  }

  function testReverts__approveToken_token_already_approved() public {
    tokens.push(IERC20(address(asset1)));

    vm.startPrank(owner);
    feeRecipient.approveToken(tokens);

    vm.expectRevert(abi.encodeWithSelector(FeeRecipientProxy.TokenAlreadyApproved.selector, address(asset1)));
    feeRecipient.approveToken(tokens);
  }

  function testFail__approveToken_nonOwner() public {
    tokens.push(IERC20(address(asset1)));

    feeRecipient.approveToken(tokens);
  }

  /*//////////////////////////////////////////////////////////////
                        VOID TOKEN APPROVAL
    //////////////////////////////////////////////////////////////*/

  function test__voidTokenApproval() public {
    tokens.push(IERC20(address(asset1)));
    tokens.push(IERC20(address(asset2)));
    approveToken(tokens);

    vm.prank(owner);
    vm.expectEmit(false, false, false, true, address(feeRecipient));
    emit TokenApprovalVoided(uint8(2));

    feeRecipient.voidTokenApproval(tokens);

    assertEq(asset1.allowance(address(feeRecipient), owner), 0);
    assertEq(asset2.allowance(address(feeRecipient), owner), 0);
    assertEq(feeRecipient.approvals(), 0);
  }

  function testRevert__voidTokenApproval_already_voided() public {
    tokens.push(IERC20(address(asset1)));

    vm.startPrank(owner);
    vm.expectRevert(abi.encodeWithSelector(FeeRecipientProxy.TokenApprovalAlreadyVoided.selector, address(asset1)));
    feeRecipient.voidTokenApproval(tokens);
  }

  function testFail__voidTokenApproval_nonOwner() public {
    tokens.push(IERC20(address(asset1)));

    feeRecipient.voidTokenApproval(tokens);
  }

  /*//////////////////////////////////////////////////////////////
                        ACCEPT OWNERSHIP
    //////////////////////////////////////////////////////////////*/

  function test__acceptOwnership() public {
    vm.prank(owner);
    feeRecipient.nominateNewOwner(address(this));

    feeRecipient.acceptOwnership();

    assertEq(feeRecipient.owner(), address(this));
    assertEq(feeRecipient.nominatedOwner(), address(0));
  }

  function testFail__acceptOwnership_approvalCount_greater_0() public {
    tokens.push(IERC20(address(asset1)));
    approveToken(tokens);

    vm.prank(owner);
    feeRecipient.nominateNewOwner(address(this));

    feeRecipient.acceptOwnership();
  }

  function testFail__acceptOwnership_nonOwner() public {
    vm.prank(owner);
    feeRecipient.nominateNewOwner(address(this));

    vm.prank(owner);
    feeRecipient.acceptOwnership();
  }
}
