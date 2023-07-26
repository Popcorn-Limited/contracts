// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {
    Math,
    ERC20,
    IERC20,
    IAdapter,
    IStrategy,
    SafeERC20,
    AdapterBase,
    IERC20Metadata,
    ERC4626Upgradeable as ERC4626
} from "../../abstracts/AdapterBase.sol";
import {
    ICarousel,
    IMarketRegistry,
    IVaultFactoryV2 as ICarouselFactory
} from "../IY2k.sol";


contract Y2KPremiumAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IMarketRegistry public marketRegistry;
    ICarouselFactory public carouselFactory;

    /**
     * @notice Initialize a new Y2k Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry The register for y2k markets.
     * @param y2kInitData to initialize y2k vaults
     * @dev This function is called by the factory contract when deploying a new vault.
     * @dev The registry will be used to fetch some market Id from the approved markets from y2k.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory y2kInitData
    ) external virtual initializer {
        __AdapterBase_init(adapterInitData);

        address _carouselFactory = abi.decode(y2kInitData, (address));

        marketRegistry = IMarketRegistry(registry);
        carouselFactory = ICarouselFactory(_carouselFactory);

        _name = string.concat(
            "VaultCraft Y2k Premium ",
            "Adapter"
        );
        _symbol = "vcY2kPremium";
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
    /// @notice The amount of y2k token shares to withdraw given an amount of adapter shares
    function convertToUnderlyingShares(
        uint256,
        uint256 shares
    ) public view override returns (uint256) {
        uint256 marketId = marketRegistry.getMarketId();
        address[2] memory vaults = carouselFactory.getVaults(marketId);

        ICarousel carousel = ICarousel(vaults[0]);
        uint256 epochId = carousel.epochs(carousel.getEpochsLength() - 1);

        uint256 balance = carousel.balanceOf(address (this), epochId);

        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(balance, supply, Math.Rounding.Up);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into premium vault
    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        uint256 marketId = marketRegistry.getMarketId(); //TODO: what parameter do we pass to fetch the right market?
        address[2] memory vaults = carouselFactory.getVaults(marketId);

        ICarousel carousel = ICarousel(vaults[0]);
        IERC20(carousel.asset()).safeApprove(carousel, type(uint256).max);
        uint256 epochId = carousel.epochs(carousel.getEpochsLength() - 1);

//        uint[] memory epochs = carousel.getAllEpochs();
//        uint256 epochId = epochs[epochs.length - 1];

        if(carousel.epochResolved(epochId)){
            //deposit into the queue with epochId 0
            carousel.deposit(
                0,
                amount,
                address (this)
            );
        } else {
            carousel.deposit(
                epochId,
                amount,
                address (this)
            );
        }
    }

    /// @notice Withdraw from the premium wallet
    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal virtual override {
        uint256 marketId = marketRegistry.getMarketId(); //TODO: what parameter do we pass to fetch the right market?
        address[2] memory vaults = carouselFactory.getVaults(marketId);

        ICarousel carousel = ICarousel(vaults[0]);
        uint256 epochId = carousel.epochs(carousel.getEpochsLength() - 1);

        uint256 shares = convertToShares(amount);
        uint256 underlyingShares = convertToUnderlyingShares(0, shares);
        carousel.withdraw(
            epochId,
            underlyingShares,
            address (this),
            address (this)
        );
    }

}
