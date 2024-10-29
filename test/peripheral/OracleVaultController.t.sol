// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {OracleVaultController, Limit} from "src/peripheral/OracleVaultController.sol";
import {MockPushOracle} from "test/mocks/MockPushOracle.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract OracleVaultControllerTest is Test {
    using FixedPointMathLib for uint256;

    OracleVaultController controller;
    MockPushOracle oracle;
    MockPausable vault;
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

        oracle = new MockPushOracle();
        vault = new MockPausable();
        asset = new MockERC20("Test Token", "TEST", 18);
        
        controller = new OracleVaultController(address(oracle), owner);

        // Setup initial state
        oracle.setPrice(address(vault), address(asset), INITIAL_PRICE, ONE);
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
        vm.expectRevert("UNAUTHORIZED");
        controller.setKeeper(address(vault), keeper);
    }

    function testUpdatePriceAsKeeper() public {
        // Setup keeper
        vm.prank(owner);
        controller.setKeeper(address(vault), keeper);

        // Update price as keeper
        vm.prank(keeper);
        controller.updatePrice(
            OracleVaultController.PriceUpdate({
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
            jump: 0.1e18,    // 10%
            drawdown: 0.2e18 // 20%
        });

        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit LimitUpdated(address(vault), Limit(0, 0), limit);
        controller.setLimit(address(vault), limit);
        
        Limit memory storedLimit = controller.limits(address(vault));
        assertEq(storedLimit.jump, limit.jump);
        assertEq(storedLimit.drawdown, limit.drawdown);
        vm.stopPrank();
    }

    function testSetLimitUnauthorized() public {
        Limit memory limit = Limit({
            jump: 0.1e18,
            drawdown: 0.2e18
        });

        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        controller.setLimit(address(vault), limit);
    }

    function testSetLimitInvalid() public {
        Limit memory limit = Limit({
            jump: 1.1e18,    // 110% - invalid
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
        limits[0] = Limit({
            jump: 0.1e18,
            drawdown: 0.2e18
        });
        limits[1] = Limit({
            jump: 0.15e18,
            drawdown: 0.25e18
        });

        vm.prank(owner);
        controller.setLimits(vaults, limits);

        Limit memory storedLimit0 = controller.limits(vaults[0]);
        Limit memory storedLimit1 = controller.limits(vaults[1]);
        
        assertEq(storedLimit0.jump, limits[0].jump);
        assertEq(storedLimit0.drawdown, limits[0].drawdown);
        assertEq(storedLimit1.jump, limits[1].jump);
        assertEq(storedLimit1.drawdown, limits[1].drawdown);
    }

    /*//////////////////////////////////////////////////////////////
                        PRICE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdatePrice() public {
        vm.prank(owner);
        controller.setLimit(address(vault), Limit({
            jump: 0.1e18,    // 10%
            drawdown: 0.2e18 // 20%
        }));

        vm.prank(owner);
        controller.updatePrice(
            OracleVaultController.PriceUpdate({
                vault: address(vault),
                asset: address(asset),
                shareValueInAssets: INITIAL_PRICE,
                assetValueInShares: ONE
            })
        );

        assertEq(
            oracle.prices(address(vault), address(asset)),
            INITIAL_PRICE
        );
    }

    function testUpdatePriceWithJumpUp() public {
        // Set limit
        vm.prank(owner);
        controller.setLimit(address(vault), Limit({
            jump: 0.1e18,    // 10%
            drawdown: 0.2e18 // 20%
        }));

        // Update price with >10% jump up
        uint256 newPrice = INITIAL_PRICE.mulDivUp(11, 10); // 11% increase
        
        vm.prank(owner);
        controller.updatePrice(
            OracleVaultController.PriceUpdate({
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
        controller.setLimit(address(vault), Limit({
            jump: 0.1e18,    // 10%
            drawdown: 0.2e18 // 20%
        }));

        // Update price with >10% jump down
        uint256 newPrice = INITIAL_PRICE.mulDivDown(89, 100); // 11% decrease
        
        vm.prank(owner);
        controller.updatePrice(
            OracleVaultController.PriceUpdate({
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
        controller.setLimit(address(vault), Limit({
            jump: 0.1e18,    // 10%
            drawdown: 0.2e18 // 20%
        }));

        // Set initial price and HWM
        controller.updatePrice(
            OracleVaultController.PriceUpdate({
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
            OracleVaultController.PriceUpdate({
                vault: address(vault),
                asset: address(asset),
                shareValueInAssets: newPrice,
                assetValueInShares: ONE.mulDivDown(ONE, newPrice)
            })
        );

        assertTrue(vault.paused());
    }

    function testUpdateMultiplePrices() public {
        OracleVaultController.PriceUpdate[] memory updates = new OracleVaultController.PriceUpdate[](2);
        
        updates[0] = OracleVaultController.PriceUpdate({
            vault: address(vault),
            asset: address(asset),
            shareValueInAssets: INITIAL_PRICE,
            assetValueInShares: ONE
        });

        updates[1] = OracleVaultController.PriceUpdate({
            vault: address(0x123),
            asset: address(asset),
            shareValueInAssets: INITIAL_PRICE,
            assetValueInShares: ONE
        });

        vm.prank(owner);
        controller.updatePrices(updates);

        assertEq(
            oracle.prices(address(vault), address(asset)),
            INITIAL_PRICE
        );
        assertEq(
            oracle.prices(address(0x123), address(asset)),
            INITIAL_PRICE
        );
    }

    /*//////////////////////////////////////////////////////////////
                        ORACLE OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function testAcceptOracleOwnership() public {
        vm.prank(owner);
        controller.acceptOracleOwnership();
    }

    function testAcceptOracleOwnershipUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        controller.acceptOracleOwnership();
    }
}

// Mock contracts needed for testing
contract MockPushOracle {
    mapping(address => mapping(address => uint256)) public prices;

    function setPrice(
        address base,
        address quote,
        uint256 bqPrice,
        uint256 qbPrice
    ) external {
        prices[base][quote] = bqPrice;
    }

    function setPrices(
        address[] memory bases,
        address[] memory quotes,
        uint256[] memory bqPrices,
        uint256[] memory qbPrices
    ) external {
        for (uint256 i = 0; i < bases.length; i++) {
            prices[bases[i]][quotes[i]] = bqPrices[i];
        }
    }
}

contract MockPausable {
    bool public paused;

    function pause() external {
        paused = true;
    }

    function unpause() external {
        paused = false;
    }
}