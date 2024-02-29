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

    // function _executeCommandsView(VmCommand memory commands) internal view returns (bytes[] memory outputState) {
    //     bytes32[] memory c = new bytes32[](1);
    //     for(uint i=0; i<commands.commands.length; i++) {
    //         c[0] = commands.commands[i];
    //         if(i==0) {
    //             // execute first command with original state 
    //             outputState = _executeView(c, commands.states);
    //         } else {
    //             // execute other commands using output state from prev op
    //             outputState = _executeView(c, outputState);
    //         }
    //     }
    // }

    // function _executeCommands(VmCommand memory commands) internal returns (bytes[] memory outputState) {
    //     bytes32[] memory c = new bytes32[](1);
    //     for(uint i=0; i<commands.commands.length; i++) {
    //         c[0] = commands.commands[i];
    //         if(i==0) {
    //             // execute first command with original state 
    //             outputState = _execute(c, commands.states);
    //         } else {
    //             // execute other commands using output state from prev op
    //             outputState = _execute(c, outputState);
    //         }
    //     }
    // }

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

struct Command {
    bytes4 sig; // function signature
    uint8 callType; // 0: delegate call, 1: call, 2: static call
    uint8[6] inputIndexes; // indexes in the state array where input variables are taken from 
    uint8 outputIndex; // index in the state array where output is written
    address target; // target contract 
}

struct InputIndex {
    bool isDynamicArray;
    uint8 index;
}

contract WeirollReader {
    function translate(bytes calldata command) public pure returns (Command memory c) {
        c.sig = bytes4(command[0:4]);
        c.callType = uint8(bytes1(command[4:5]));
        c.inputIndexes[0] = uint8(bytes1(command[5:6]));
        c.inputIndexes[1] = uint8(bytes1(command[6:7]));
        c.inputIndexes[2] = uint8(bytes1(command[7:8]));
        c.inputIndexes[3] = uint8(bytes1(command[8:9]));
        c.inputIndexes[4] = uint8(bytes1(command[9:10]));
        c.inputIndexes[5] = uint8(bytes1(command[10:11]));
        c.outputIndex = uint8(bytes1(command[11:12]));
        c.target = address(bytes20(command[12:32]));
    }
    
    // TODO in the same array we can have both static and dynamic
    function toByteCommand(
        string memory functionSig, uint8 callType, InputIndex[6] memory inputIndexes, uint8 outputIndex, address target
    ) public view returns (bytes32 command) {
       bytes memory inputIn;

        for(uint i=0; i<6; i++){
            InputIndex memory index = inputIndexes[i];
            uint256 ind = index.index;

            if(!index.isDynamicArray){
                inputIn = abi.encodePacked(
                    inputIn, 
                    bytes1(bytes32(abi.encode(ind)) << 31*8)
                );
            } else {
                // TODO encode arrays
                uint256 actualNumb;
                if(ind == 255) {
                    actualNumb = ind;
                } else {
                    // append 1 and 1 to the MSB cause it's dynamic input
                    actualNumb = 2**6 + ind;
                }
                inputIn = abi.encodePacked(
                    inputIn, 
                    bytes1(bytes32(abi.encode(actualNumb)) << 31*8)
                );
            }
        }

       // TODO output index with dynamic output variable 
       command = bytes32(abi.encodePacked(
            bytes4(keccak256(abi.encodePacked(functionSig))),
            bytes1(callType),
            inputIn,
            bytes1(outputIndex),
            bytes20(target))
        );
    }
}

// contract MockTarget {
//     function tryOut(uint256[] memory test, uint256 val) public {
//         console.log(test[0]);
//                 console.log(test[1]);
//         console.log(test[2]);
//         console.log(test[3]);
//         console.log(test[4]);
//         console.log(val);
//     }

//     fallback() external{
//         console.log("FALL");
//     }
// }
