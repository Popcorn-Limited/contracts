// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

contract EnhancedTest is Test {
  function assertApproxGeAbs(uint256 a, uint256 b, uint256 maxDelta) internal {
    if (!(a >= b)) {
      uint256 dt = b - a;
      if (dt > maxDelta) {
        emit log("Error: a >=~ b not satisfied [uint]");
        emit log_named_uint("   Value a", a);
        emit log_named_uint("   Value b", b);
        emit log_named_uint(" Max Delta", maxDelta);
        emit log_named_uint("     Delta", dt);
        fail();
      }
    }
  }

  function assertApproxGeAbs(uint256 a, uint256 b, uint256 maxDelta, string memory err) internal {
    if (!(a >= b)) {
      uint256 dt = b - a;
      if (dt > maxDelta) {
        emit log(err);
        emit log("Error: a >=~ b not satisfied [uint]");
        emit log_named_uint("   Value a", a);
        emit log_named_uint("   Value b", b);
        emit log_named_uint(" Max Delta", maxDelta);
        emit log_named_uint("     Delta", dt);
        fail();
      }
    }
  }

  function assertApproxLeAbs(uint256 a, uint256 b, uint256 maxDelta) internal {
    if (!(a <= b)) {
      uint256 dt = a - b;
      if (dt > maxDelta) {
        emit log("Error: a <=~ b not satisfied [uint]");
        emit log_named_uint("   Value a", a);
        emit log_named_uint("   Value b", b);
        emit log_named_uint(" Max Delta", maxDelta);
        emit log_named_uint("     Delta", dt);
        fail();
      }
    }
  }

  function assertApproxLeAbs(uint256 a, uint256 b, uint256 maxDelta, string memory err) internal {
    if (!(a <= b)) {
      uint256 dt = a - b;
      if (dt > maxDelta) {
        emit log(err);
        emit log("Error: a <=~ b not satisfied [uint]");
        emit log_named_uint("   Value a", a);
        emit log_named_uint("   Value b", b);
        emit log_named_uint(" Max Delta", maxDelta);
        emit log_named_uint("     Delta", dt);
        fail();
      }
    }
  }
}
