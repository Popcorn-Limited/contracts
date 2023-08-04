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
    QueueItem,
    ICarousel,
    IVaultFactoryV2 as ICarouselFactory
} from "../IY2k.sol";


contract Y2KCollateralAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    ICarousel public carousel;
    ICarouselFactory public carouselFactory;

    error EpochNotResolved();
    error InvalidPremiumVault();

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

        (address _carouselFactory, uint256 _marketId) = abi.decode(y2kInitData, (address, uint256));
        carouselFactory = ICarouselFactory(_carouselFactory);

        address[2] memory vaults = carouselFactory.getVaults(_marketId);
        if(vaults[1] == address(0)){
            revert InvalidPremiumVault();
        }
        carousel = ICarousel(vaults[1]);

        IERC20(carousel.asset()).safeApprove(address(carousel), type(uint256).max);

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
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Emulate y2k total asset calculation to return the total assets of the vault.
    function _totalAssets() internal view override returns (uint256) {
        //implemented based on deposit into the y2k open epoch not into deposit queue
        //this is also equivalent to the shares of the vault in the y2k adapter.
        ICarousel _carousel = carousel;
        uint256 epochId = _getLatestEpochId(_carousel);
        return _carousel.balanceOf(address (this), epochId);
    }

    /// @notice The amount of y2k token shares to withdraw given an amount of adapter shares
    function convertToUnderlyingShares(
        uint256,
        uint256 shares
    ) public view override returns (uint256) {
        ICarousel _carousel = carousel;
        uint256 epochId = _getLatestEpochId(_carousel);

        uint256 balance = _carousel.balanceOf(address (this), epochId);
        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(balance, supply, Math.Rounding.Down);
    }

    /*//////////////////////////////////////////////////////////////
                   DEPOSIT/WITHDRAWAL LIMIT LOGIC
   //////////////////////////////////////////////////////////////*/
    /// @dev When epoch is active return 0, else return amount
    function maxWithdraw(address owner) public view override returns (uint256) {
        if (paused()) return 0;

        ICarousel _carousel = carousel;
        uint256 epochId = _getLatestEpochId(_carousel);
        if (!_carousel.epochResolved(epochId)) return 0;

        return convertToAssets(balanceOf(owner));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into premium vault
    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        ICarousel _carousel = carousel;
        if(amount < _carousel.minQueueDeposit()) return;

        uint256 epochId = _getLatestEpochId(_carousel);
        (uint40 _epochBegin, , ) = _carousel.getEpochConfig(epochId);
        bool epochHasStarted = block.timestamp > _epochBegin;
        if(epochHasStarted){
            //deposit into the queue with epochId 0
            _carousel.deposit(
                0,
                amount,
                address (this)
            );
        } else {
            _carousel.deposit(
                epochId,
                amount,
                address (this)
            );
        }
        //_carousel.enListInRollover(_totalAssets(), epochId, address(this));
    }

    /// @notice Withdraw from the premium wallet
    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal virtual override {
        //during withdraw the amount of shares passed in will be previewed for a gain or a loss before asset transfer
        if(_totalAssets() == 0) return;

        ICarousel _carousel = carousel;
        uint256 epochId = _getLatestEpochId(_carousel);

        uint256 shares = convertToShares(_totalAssets());
        uint256 underlyingShares = convertToUnderlyingShares(0, shares);

        if(!_carousel.epochResolved(epochId)) revert EpochNotResolved();

        //_carousel.deListInRollover(address (this));
        _carousel.withdraw(
            epochId,
            underlyingShares,
            address (this),
            address (this)
        );
    }

    function _getLatestEpochId(ICarousel _carousel) internal view returns(uint256 epochId) {
        epochId = _carousel.epochs(_carousel.getEpochsLength() - 1);
    }
}
