// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../../abstracts/AdapterBase.sol";
import {IMorphoAave} from "./IMorphoAave.sol";
import {IAaveLens} from "./IAaveLens.sol";
import {Types} from "../Types.sol";
import {IPermissionRegistry} from "../../../../interfaces/vault/IPermissionRegistry.sol";

contract MorphoAaveAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    address public poolToken;
    IMorphoAave public morpho;
    IAaveLens public lens;

    error NotEndorsed(address morpho);
    error MarketNotCreated(address poolToken);
    error SupplyIsPaused(address poolToken);

    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory morphoInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        (address _poolToken, address _morpho, address _lens) = abi.decode(
            morphoInitData,
            (address, address, address)
        );

        if (!IPermissionRegistry(registry).endorsed(_morpho))
            revert NotEndorsed(_morpho);

        morpho = IMorphoAave(_morpho);
        lens = IAaveLens(_lens);

        if (!lens.isMarketCreated(_poolToken))
            revert MarketNotCreated(_poolToken);

        Types.MarketPauseStatus memory marketStatus = lens.getMarketPauseStatus(
            _poolToken
        );
        if (marketStatus.isSupplyPaused) revert SupplyIsPaused(_poolToken);

        poolToken = _poolToken;

        address entryPositionsManager = morpho.entryPositionsManager();

        _name = string.concat(
            "Popcorn Morpho Aave",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("popMA-", IERC20Metadata(asset()).symbol());

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
            poolToken,
            address(this)
        );
        return totalBalance;
    }

    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        morpho.supply(poolToken, amount);
    }

    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal virtual override {
        morpho.withdraw(poolToken, amount);
    }
}
