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


contract Y2KAdapter is AdapterBase {
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
            "VaultCraft Y2k Collateral ",
            "Adapter"
        );
        _symbol = "vcY2kCollateral";
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
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into premium vault
    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        uint256 marketId = marketRegistry.getMarketId(); //TODO: what parameter do we pass to fetch the right market?
        address[2] memory vaults = carouselFactory.getVaults(marketId);
        ICarousel carousel = ICarousel(vaults[1]);

        uint[] memory epochs = carousel.getAllEpochs();
        uint256 epochId = epochs[epochs.length - 1];

        IERC20(carousel.asset()).safeApprove(carousel, type(uint256).max);

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
        //check that amount of shares to withdraw covers withdraw amount
        //check the deposit queue if there is some amount to withdraw
        //check the withdraw queue for some withdraw amount if necessary
    }
}
