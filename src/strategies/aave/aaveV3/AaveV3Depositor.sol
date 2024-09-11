// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "src/strategies/BaseStrategy.sol";
import {ILendingPool, IAaveIncentives, IAToken, IProtocolDataProvider, DataTypes} from "src/interfaces/external/aave/IAaveV3.sol";

/**
 * @title   AaveV3 Adapter
 * @author  RedVeil
 * @notice  ERC4626 wrapper for AaveV3 Vaults.
 */
contract AaveV3Depositor is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The Aave aToken contract
    IAToken public aToken;

    /// @notice The Aave liquidity mining contract
    IAaveIncentives public aaveIncentives;

    /// @notice Check to see if Aave liquidity mining is active
    bool public isActiveIncentives;

    /// @notice The Aave LendingPool contract
    ILendingPool public lendingPool;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    error DifferentAssets(address asset, address underlying);

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoDeposit_ Controls if `protocolDeposit` gets called on deposit
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function initialize(
        address asset_,
        address owner_,
        bool autoDeposit_,
        bytes memory strategyInitData_
    ) external initializer {
        address _aaveDataProvider = abi.decode(strategyInitData_, (address));

        (address _aToken, , ) = IProtocolDataProvider(_aaveDataProvider)
            .getReserveTokensAddresses(asset_);

        aToken = IAToken(_aToken);
        if (aToken.UNDERLYING_ASSET_ADDRESS() != asset_) {
            revert DifferentAssets(aToken.UNDERLYING_ASSET_ADDRESS(), asset_);
        }

        lendingPool = ILendingPool(aToken.POOL());
        aaveIncentives = IAaveIncentives(aToken.getIncentivesController());

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(asset_).approve(address(lendingPool), type(uint256).max);

        _name = string.concat(
            "VaultCraft AaveV3 ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcAv3-", IERC20Metadata(asset()).symbol());
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

    function _totalAssets() internal view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /// @notice The token rewarded if the aave liquidity mining is active
    function rewardTokens() external view override returns (address[] memory) {
        return aaveIncentives.getRewardsByAsset(asset());
    }

    function convertToUnderlyingShares(
        uint256 assets,
        uint256 shares
    ) public view override returns (uint256) {
        revert();
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into aave lending pool
    function _protocolDeposit(
        uint256 assets,
        uint256,
        bytes memory
    ) internal override {
        lendingPool.supply(asset(), assets, address(this), 0);
    }

    /// @notice Withdraw from lending pool
    function _protocolWithdraw(
        uint256 assets,
        uint256,
        bytes memory
    ) internal override {
        lendingPool.withdraw(asset(), assets, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim additional rewards given that it's active.
    function claim() internal override returns (bool success) {
        if (address(aaveIncentives) == address(0)) return false;

        address[] memory _assets = new address[](1);
        _assets[0] = address(aToken);

        try aaveIncentives.claimAllRewardsToSelf(_assets) {
            success = true;
        } catch {}
    }

    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        claim();

        address[] memory _rewardTokens = aaveIncentives.getRewardsByAsset(
            asset()
        );

        for (uint256 i; i < _rewardTokens.length; i++) {
            uint256 balance = IERC20(_rewardTokens[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(_rewardTokens[i]).transfer(msg.sender, balance);
            }
        }

        uint256 assetAmount = abi.decode(data, (uint256));

        if (assetAmount == 0) revert ZeroAmount();

        IERC20(asset()).transferFrom(msg.sender, address(this), assetAmount);

        _protocolDeposit(assetAmount, 0, bytes(""));

        emit Harvested();
    }
}
