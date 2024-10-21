// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test, console, console2} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ILBT} from "src/interfaces/external/lfj/ILBT.sol";
import {ILBRouter} from "src/interfaces/external/lfj/ILBRouter.sol";

struct CallStruct {
    address target;
    bytes4 data;
}

event LogBytes4(bytes4);
event LogBytes(bytes);

contract Tester is Test {
    function setUp() public {
        vm.createSelectFork("avalanche", 52057786);
    }

    function test__stuff() public {
        vm.prank(0x799d4C5E577cF80221A076064a2054430D2af5cD);
        IERC20(0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd).transfer(
            address(this),
            100e18
        );

        IERC20(0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd).approve(
            0x18556DA13313f3532c54711497A8FedAC273220E,
            100e18
        );

        int256[] memory deltaIds = new int256[](3);
        deltaIds[0] = 0;
        deltaIds[1] = 1;
        deltaIds[2] = 2;

        uint256[] memory distributionX = new uint256[](3);
        distributionX[0] = 20e18; // 20%
        distributionX[1] = 40e18; // 40%
        distributionX[2] = 40e18; // 40%

        uint256[] memory distributionY = new uint256[](3);
        distributionY[0] = 1e18;
        distributionY[1] = 0;
        distributionY[2] = 0;

        ILBRouter.LiquidityParameters memory params = ILBRouter.LiquidityParameters({
            tokenX: 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd,
            tokenY: 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7,
            binStep: 25,
            amountX: 100e18,
            amountY: 0,
            amountXMin: 99.9e18,
            amountYMin: 0,
            activeIdDesired: 8386853,
            idSlippage: 1,
            deltaIds: deltaIds,
            distributionX: distributionX,
            distributionY: distributionY,
            to: address(this),
            refundTo: address(this),
            deadline: 1729510546
        });

        ILBRouter(0x18556DA13313f3532c54711497A8FedAC273220E)
            .addLiquidityNATIVE(params);
    }
}
