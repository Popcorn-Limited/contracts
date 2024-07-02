// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "src/strategies/BaseStrategy.sol";
import {ICToken, ICometRewarder} from "./ICompoundV3.sol";

/**
 * @title   CompoundV3 Compounder
 * @author  RedVeil
 * @notice  ERC4626 wrapper for CompoundV3 Vaults.
 */
contract CompoundV3Compounder is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The Compound cToken contract
    ICToken public cToken;

    ICometRewarder public rewarder;
    IERC20 public rewardToken;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

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
        (address cToken_, address rewarder_, address rewardToken_) = abi.decode(
            strategyInitData_,
            (address, address, address)
        );

        cToken = ICToken(cToken_);
        rewarder = ICometRewarder(rewarder_);
        rewardToken = IERC20(rewardToken_);

        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        IERC20(asset_).approve(cToken_, type(uint256).max);

        _name = string.concat(
            "VaultCraft CompoundV3 ",
            IERC20Metadata(asset_).name(),
            " Compounder"
        );
        _symbol = string.concat("vcCv3-", IERC20Metadata(asset_).symbol());
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
        return cToken.balanceOf(address(this));
    }

    /// @notice The token rewarded from the convex reward contract
    function rewardTokens() external view override returns (address[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(rewardToken);
        return _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(
        uint256 assets,
        uint256,
        bytes memory
    ) internal override {
        cToken.supply(asset(), assets);
    }

    function _protocolWithdraw(
        uint256 assets,
        uint256,
        bytes memory
    ) internal override {
        cToken.withdraw(asset(), assets);
    }

    /// @notice Claim liquidity mining rewards given that it's active
    function claim() internal override returns (bool success) {
        try rewarder.claim(address(cToken), address(this), true) {
            success = true;
        } catch {}
    }

    /**
     * @notice Claim rewards and compound them into the vault
     */
    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        claim();

        rewardToken.transfer(msg.sender, rewardToken.balanceOf(address(this)));

        uint256 assetAmount = abi.decode(data, (uint256));

        if (assetAmount == 0) revert ZeroAmount();

        IERC20(asset()).transferFrom(msg.sender, address(this), assetAmount);

        _protocolDeposit(assetAmount, 0, bytes(""));
    }
}
