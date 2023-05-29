// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../../abstracts/AdapterBase.sol";
import {IMorphoCompound} from "./IMorphoCompound.sol";
import {IComptroller} from "./IComptroller.sol";
import {ICompoundLens} from "./ICompoundLens.sol";
import {Types} from "../Types.sol";
import {WithRewards, IWithRewards} from "../../abstracts/WithRewards.sol";
import {IPermissionRegistry} from "../../../../interfaces/vault/IPermissionRegistry.sol";

contract MorphoCompoundAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    address public poolToken;
    IMorphoCompound public morpho;
    ICompoundLens public lens;

    error NotEndorsed(address morpho);
    error MarketNotCreated(address poolToken);
    error SupplyIsPaused(address poolToken);

    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory morphoInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);
        (
            address _poolToken,
            address _morpho,
            address _lens
        ) = abi.decode(morphoInitData, (address, address, address));

        if (!IPermissionRegistry(registry).endorsed(_morpho))
            revert NotEndorsed(_morpho);

        morpho = IMorphoCompound(_morpho);
        lens = ICompoundLens(_lens);

        if (!lens.isMarketCreated(_poolToken))
            revert MarketNotCreated(_poolToken);

        Types.MarketPauseStatus memory marketStatus = lens.getMarketPauseStatus(
            _poolToken
        );
        if (marketStatus.isSupplyPaused) revert SupplyIsPaused(_poolToken);

        poolToken = _poolToken;

        address positionsManager = morpho.positionsManager();

        _name = string.concat(
            "Popcorn Morpho Compound",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("popMC-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).approve(address(morpho), type(uint256).max);
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

    function _totalAssets() internal view override returns (uint256) {
        (, , uint256 totalBalance) = lens.getCurrentSupplyBalanceInOf(
            poolToken, // the poolToken market
            address(this) // the address of the user you want to know the supply of
        );
        return totalBalance;
    }

    function rewardTokens() external view override returns (address[] memory) {
        address[] memory _rewardTokens = new address[](1);
        address _comptroller = morpho.comptroller();
        address _comp = IComptroller(_comptroller).getCompAddress();
        _rewardTokens[0] = _comp;
        return _rewardTokens;
    }

    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        morpho.supply(poolToken, amount);
    }

    function _protocolWithdraw(
        uint256,
        uint256 shares
    ) internal virtual override {
        uint256 amount = _convertToAssets(shares, Math.Rounding.Down);
        morpho.withdraw(poolToken, amount);
    }

    function claim() public override onlyStrategy {
        address[] memory _cTokenAddresses = new address[](1);
        _cTokenAddresses[0] = poolToken;
        morpho.claimRewards(_cTokenAddresses, false);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public pure override(WithRewards, AdapterBase) returns (bool) {
        return
            interfaceId == type(IWithRewards).interfaceId ||
            interfaceId == type(IAdapter).interfaceId;
    }
}
