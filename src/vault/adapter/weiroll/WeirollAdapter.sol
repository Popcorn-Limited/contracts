// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../abstracts/AdapterBase.sol";
import {IPermissionRegistry} from "../../../interfaces/vault/IPermissionRegistry.sol";
import {VM} from "./VM.sol";

/**
 * @title   ERC4626 Universal Adapter
 * @author  Andrea Di Nenno
 * @notice  ERC4626 wrapper that aims at supporting any underlying protocol logic using the Weiroll Library
 *
 */

struct VmCommand {
    bytes32[] commands;
    bytes[] states; // each slot is a 32byte abi encoded arg
}

contract WeirollUniversalAdapter is AdapterBase, VM {
    using SafeERC20 for IERC20;

    string internal _name;
    string internal _symbol;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error NotEndorsed();
    error InvalidAsset();

    VmCommand depositCommands;
    VmCommand withdrawCommands;
    VmCommand totalAssetsCommands;
    VmCommand harvestCommands;

    /**
     * @notice Initialize a new generic Vault Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev `_vault` - The address of the 4626 vault to use.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address toApprove,
        bytes memory commands
    ) external initializer {
        __AdapterBase_init(adapterInitData);
        
        // address _vault = abi.decode(vaultInitData, (address));
        _name = string.concat(
            "VaultCraft ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).approve(address(toApprove), type(uint256).max);

        _initCommands(commands);
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

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.
    function _totalAssets() internal view override returns (uint256) {
        // output is last element of states arrays   
        uint256 indexOut = totalAssetsCommands.states.length - 1;
    
        bytes[] memory outputState = _executeView(totalAssetsCommands.commands, totalAssetsCommands.states);
        return abi.decode(outputState[indexOut], (uint256));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/
    function _protocolDeposit(
        uint256 amount,
        uint256 
    ) internal override {
        depositCommands.states[0] = abi.encode(amount); // push amount to state 0
        depositCommands.states[1] = abi.encode(msg.sender); // push sender to state 1 

        _execute(depositCommands.commands, depositCommands.states);
    }

    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal override {
        withdrawCommands.states[0] = abi.encode(amount); // push amount to state 0
        withdrawCommands.states[1] = abi.encode(msg.sender); // push sender to state 1 

        _execute(withdrawCommands.commands, withdrawCommands.states);
    }

    function harvest() public override takeFees {
        bytes[] memory state = _execute(harvestCommands.commands, harvestCommands.states);
    }

    function _initCommands(bytes memory commands) internal {
         (
            bytes32[] memory c, 
            bytes[] memory s,
            bytes32[] memory cW, 
            bytes[] memory sW,
            bytes32[] memory cT, 
            bytes[] memory sT,
            bytes32[] memory cH, 
            bytes[] memory sH
        ) = abi.decode(commands, (bytes32[],bytes[],bytes32[],bytes[],bytes32[],bytes[],bytes32[],bytes[]));
        
        // DEPOSIT 
        for(uint i=0; i<c.length; i++) {
            depositCommands.commands.push(c[i]);
        }
        depositCommands.states.push(abi.encode(0)); // leave slot 0 empty for amount 
        depositCommands.states.push(abi.encode(0)); // leave slot 1 empty for msg.sender 

        for(uint i=0; i<s.length; i++) {
            depositCommands.states.push(s[i]);
        }

        // WITHDRAW
        for(uint i=0; i<cW.length; i++) {
            withdrawCommands.commands.push(cW[i]);
        }
        withdrawCommands.states.push(""); // leave slot 0 empty for amount 

        for(uint i=0; i<sW.length; i++) {
            withdrawCommands.states.push(sW[i]);
        }

        // TOTAL ASSETS 
        for(uint i=0; i<cT.length; i++) {
            totalAssetsCommands.commands.push(cT[i]);
        }
        // push passed args - usually none
        for(uint i=0; i<sT.length; i++) {
            totalAssetsCommands.states.push(sT[i]);
        }
        totalAssetsCommands.states.push(abi.encode(0)); // push empty slot to get output value written

        // HARVEST
        for(uint i=0; i<cH.length; i++) {
            harvestCommands.commands.push(cH[i]);
        }
        for(uint i=0; i<sH.length; i++) {
            harvestCommands.states.push(sH[i]);
        }
    }
}
