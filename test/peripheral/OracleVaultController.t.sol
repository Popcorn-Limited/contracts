// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {OracleVaultController, Limit, PriceUpdate} from "src/peripheral/oracles/OracleVaultController.sol";
import {PushOracle} from "src/peripheral/oracles/adapter/pushOracle/PushOracle.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";

contract OracleVaultControllerTest is Test {
    using FixedPointMathLib for uint256;

    OracleVaultController controller;
    PushOracle oracle;
    MockERC4626 vault;
    MockERC20 asset;

    address owner = address(0x1);
    address keeper = address(0x2);
    address alice = address(0x3);

    uint256 constant ONE = 1e18;
    uint256 constant INITIAL_PRICE = 1e18;

    event KeeperUpdated(address vault, address previous, address current);
    event LimitUpdated(address vault, Limit previous, Limit current);

    function setUp() public {
        vm.label(owner, "owner");
        vm.label(keeper, "keeper");
        vm.label(alice, "alice");

        oracle = new PushOracle(owner);
        vault = new MockERC4626();
        asset = new MockERC20("Test Token", "TEST", 18);

        controller = new OracleVaultController(address(oracle), owner);

        // Setup initial state
        vm.startPrank(owner);
        oracle.nominateNewOwner(address(controller));
        controller.acceptOracleOwnership();
        controller.addVault(address(vault));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        KEEPER MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetKeeper() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true);
        emit KeeperUpdated(address(vault), address(0), keeper);
        controller.setKeeper(address(vault), keeper);

        assertEq(controller.keepers(address(vault)), keeper);
        vm.stopPrank();
    }

    function testSetKeeperUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert("Owned/not-owner");
        controller.setKeeper(address(vault), keeper);
    }

    function testUpdatePriceAsKeeper() public {
        // Setup keeper
        vm.prank(owner);
        controller.setKeeper(address(vault), keeper);

        // Update price as keeper
        vm.prank(keeper);
        controller.updatePrice(
            PriceUpdate({
                vault: address(vault),
                asset: address(asset),
                shareValueInAssets: INITIAL_PRICE,
                assetValueInShares: ONE
            })
        );
    }

    /*//////////////////////////////////////////////////////////////
                        LIMIT MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetLimit() public {
        Limit memory limit = Limit({
            jump: 0.1e18, // 10%
            drawdown: 0.2e18 // 20%
        });

        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true);
        emit LimitUpdated(address(vault), Limit(0, 0), limit);
        controller.setLimit(address(vault), limit);

        (uint256 jump, uint256 drawdown) = controller.limits(address(vault));
        assertEq(jump, limit.jump);
        assertEq(drawdown, limit.drawdown);
        vm.stopPrank();
    }

    function testSetLimitUnauthorized() public {
        Limit memory limit = Limit({jump: 0.1e18, drawdown: 0.2e18});

        vm.prank(alice);
        vm.expectRevert("Owned/not-owner");
        controller.setLimit(address(vault), limit);
    }

    function testSetLimitInvalid() public {
        Limit memory limit = Limit({
            jump: 1.1e18, // 110% - invalid
            drawdown: 0.2e18
        });

        vm.prank(owner);
        vm.expectRevert("Invalid limit");
        controller.setLimit(address(vault), limit);
    }

    function testSetMultipleLimits() public {
        address[] memory vaults = new address[](2);
        vaults[0] = address(vault);
        vaults[1] = address(0x123);

        Limit[] memory limits = new Limit[](2);
        limits[0] = Limit({jump: 0.1e18, drawdown: 0.2e18});
        limits[1] = Limit({jump: 0.15e18, drawdown: 0.25e18});

        vm.prank(owner);
        controller.setLimits(vaults, limits);

        (uint256 jump0, uint256 drawdown0) = controller.limits(vaults[0]);
        (uint256 jump1, uint256 drawdown1) = controller.limits(vaults[1]);

        assertEq(jump0, limits[0].jump);
        assertEq(drawdown0, limits[0].drawdown);
        assertEq(jump1, limits[1].jump);
        assertEq(drawdown1, limits[1].drawdown);
    }

    /*//////////////////////////////////////////////////////////////
                        PRICE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdatePrice() public {
        vm.prank(owner);
        controller.setLimit(
            address(vault),
            Limit({
                jump: 0.1e18, // 10%
                drawdown: 0.2e18 // 20%
            })
        );

        vm.prank(owner);
        controller.updatePrice(
            PriceUpdate({
                vault: address(vault),
                asset: address(asset),
                shareValueInAssets: INITIAL_PRICE,
                assetValueInShares: ONE
            })
        );

        assertEq(oracle.prices(address(vault), address(asset)), INITIAL_PRICE);
    }

    function testUpdatePriceWithJumpUp() public {
        // Set limit
        vm.prank(owner);
        controller.setLimit(
            address(vault),
            Limit({
                jump: 0.1e18, // 10%
                drawdown: 0.2e18 // 20%
            })
        );

        // Update price with >10% jump up
        uint256 newPrice = INITIAL_PRICE.mulDivUp(1.11e18, 1e18); // 11% increase

        vm.prank(owner);
        controller.updatePrice(
            PriceUpdate({
                vault: address(vault),
                asset: address(asset),
                shareValueInAssets: newPrice,
                assetValueInShares: ONE.mulDivDown(ONE, newPrice)
            })
        );

        assertTrue(vault.paused());
    }

    function testUpdatePriceWithJumpDown() public {
        // Set limit
        vm.prank(owner);
        controller.setLimit(
            address(vault),
            Limit({
                jump: 0.1e18, // 10%
                drawdown: 0.2e18 // 20%
            })
        );

        // Update price with >10% jump down
        uint256 newPrice = INITIAL_PRICE.mulDivDown(0.89e18, 1e18); // 11% decrease

        vm.prank(owner);
        controller.updatePrice(
            PriceUpdate({
                vault: address(vault),
                asset: address(asset),
                shareValueInAssets: newPrice,
                assetValueInShares: ONE.mulDivDown(ONE, newPrice)
            })
        );

        assertTrue(vault.paused());
    }

    function testUpdatePriceWithDrawdown() public {
        // Set limit and initial high water mark
        vm.startPrank(owner);
        controller.setLimit(
            address(vault),
            Limit({
                jump: 0.1e18, // 10%
                drawdown: 0.2e18 // 20%
            })
        );

        // Set initial price and HWM
        controller.updatePrice(
            PriceUpdate({
                vault: address(vault),
                asset: address(asset),
                shareValueInAssets: INITIAL_PRICE,
                assetValueInShares: ONE
            })
        );
        vm.stopPrank();

        // Update price with >20% drawdown from HWM
        uint256 newPrice = INITIAL_PRICE.mulDivDown(79, 100); // 21% decrease

        vm.prank(owner);
        controller.updatePrice(
            PriceUpdate({
                vault: address(vault),
                asset: address(asset),
                shareValueInAssets: newPrice,
                assetValueInShares: ONE.mulDivDown(ONE, newPrice)
            })
        );

        assertTrue(vault.paused());
    }

    function testUpdateMultiplePrices() public {
        // Add the second vault
        MockERC4626 vault2 = new MockERC4626();
        vm.prank(owner);
        controller.addVault(address(vault2));

        PriceUpdate[]
            memory updates = new PriceUpdate[](2);

        updates[0] = PriceUpdate({
            vault: address(vault),
            asset: address(asset),
            shareValueInAssets: INITIAL_PRICE,
            assetValueInShares: ONE
        });

        updates[1] = PriceUpdate({
            vault: address(vault2),
            asset: address(asset),
            shareValueInAssets: INITIAL_PRICE,
            assetValueInShares: ONE
        });

        vm.prank(owner);
        controller.updatePrices(updates);

        assertEq(oracle.prices(address(vault), address(asset)), INITIAL_PRICE);
        assertEq(oracle.prices(address(vault2), address(asset)), INITIAL_PRICE);
    }
}
