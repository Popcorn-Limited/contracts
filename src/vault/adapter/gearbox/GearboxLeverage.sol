// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20} from "../../abstracts/AdapterBase.sol";
import {ICreditFacadeV3, MultiCall, ICreditFacadeV3Multicall} from "./IGearboxV3.sol";

/**
 * @title   Gearbox Passive Pool Adapter
 * @author  RedVeil
 * @notice  ERC4626 wrapper for Gearbox's passive pools.
 *
 * An ERC4626 compliant Wrapper for https://github.com/Gearbox-protocol/core-v2/blob/main/contracts/pool/PoolService.sol.
 * Allows wrapping Passive pools.
 */
contract GearboxLeverage is AdapterBase {
    using SafeERC20 for IERC20;

    string internal _name;
    string internal _symbol;

    ICreditFacadeV3 public creditFacade;

    /*//////////////////////////////////////////////////////////////
                                INITIALIZATION
   //////////////////////////////////////////////////////////////*/

    error WrongPool();

    /**
     * @notice Initialize a new Gearbox Passive Pool Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param addressProvider GearboxAddressProvider
     * @param gearboxInitData Encoded data for the Lido adapter initialization.
     * @dev `_pid` - The poolId for lpToken.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address,
        bytes memory gearboxInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        (address _creditFacade, address _creditManager) = abi.decode(
            gearboxInitData,
            (address, address)
        );

        creditFacade = ICreditFacadeV3(_creditFacade);
        //creditManager = _creditManager;

        ICreditFacadeV3(_creditFacade).openCreditAccount(address(this), [], 0);

        _name = string.concat(
            "VaultCraft GearboxLeverage ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-gl-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).approve(_creditManager, type(uint256).max);
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

    /// @dev Calculate totalAssets by converting the total diesel tokens to underlying amount
    function _totalAssets() internal view override returns (uint256) {}

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LIMIT LOGIC
  //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public view override returns (uint256) {}

    function maxMint(address) public view override returns (uint256) {}

    /// @dev When poolService is paused and we didnt withdraw before (paused()) return 0
    function maxWithdraw(
        address owner
    ) public view override returns (uint256) {}

    /// @dev When poolService is paused and we didnt withdraw before (paused()) return 0
    function maxRedeem(address owner) public view override returns (uint256) {}

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 assets, uint256) internal override {
        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: address(creditFacade),
            callData: abi.encodeCall(
                ICreditFacadeV3Multicall.addCollateral,
                (asset(), assets)
            )
        });

        creditFacade.multicall(calls);
    }

    function _protocolWithdraw(uint256 assets, uint256) internal override {
        // TODO make a liquidation check

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: address(creditFacade),
            callData: abi.encodeCall(
                ICreditFacadeV3Multicall.withdrawCollateral,
                (asset(), assets, address(this))
            )
        });

        creditFacade.multicall(calls);
    }


    function _reduceDebtLevel() internal {
      // Withdraw assets
      // Decrease Debt
    }

    function _increaseDebtLevel() internal {
      // increase Debt
      // Deposit Assets
    }
}
