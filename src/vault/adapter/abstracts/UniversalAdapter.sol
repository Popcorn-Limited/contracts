// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../abstracts/AdapterBase.sol";
import {IPermissionRegistry} from "../../../interfaces/vault/IPermissionRegistry.sol";

/**
 * @title   ERC4626 Universal Adapter
 * @author  Andrea Di Nenno
 * @notice  ERC4626 wrapper that aims at supporting any underlying protocol logic
 *
 */
contract UniversalAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    string internal _name;
    string internal _symbol;

    enum Operations {ADD, SUB, MUL, SKIP}

    struct DynamicParam {
        uint slotPosition; // position on the calldataParams to insert encoded dynamic value
    }

    // WIP 
    struct IntermediateOperation {
        Operations operation;  // to dictate what to do in between calls 
        uint value; // operand on the operation
        bool isFirstOperand; //if value is first or second operand in operation
    }

    struct ExecutionData {
        bytes4 sig; // function signature
        bytes[] calldataParams; // array of ordered calldata parameters, Each parameter is a bytes slot in the array - fixed params in the calldata are set while dynamic params are set to 0
        DynamicParam[] dynamicParams; // array of Dynamic Params, needed to create the actual final calldata 
        address target; // array of target contracts to execute calls to 
        IntermediateOperation intermediateOp; // array of intermediate operations to perform to values in between external calls 
    }

    ExecutionData[] depositData; // array of different operations to carry out during protocol deposit 
    ExecutionData[] totalAssetsData; // array of different operations to carry out during protocol total assets call 
    ExecutionData[] withdrawData; // array of different operations to carry out during protocol withdraw 


    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error NotEndorsed();
    error InvalidAsset();

    // TODO proper initialization - approvals
    /**
     * @notice Initialize a new generic Vault Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev `_vault` - The address of the 4626 vault to use.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address,
        bytes memory
    ) external initializer {
        __AdapterBase_init(adapterInitData);
        
        // address _vault = abi.decode(vaultInitData, (address));
        _name = string.concat(
            "VaultCraft ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-", IERC20Metadata(asset()).symbol());

        // IERC20(asset()).approve(address(vault), type(uint256).max);
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

    // right now it assumes a single operation is performed on each call
    // TODO how do we perform sanity checks?
    function setProtocolData(
        uint256 type_,
        bytes4 sig_,
        bytes[] memory calldataParams_, 
        address target_, 
        DynamicParam[] memory dynamicParams_
    ) public {
        ExecutionData storage data;
        if (type_ == 0) {
            data = depositData.push();
        } else if (type_ == 1) {
            data = totalAssetsData.push();
        } else {
            data = withdrawData.push();
        }

        data.sig = sig_;
        data.calldataParams = calldataParams_;
        data.target = target_;
        data.dynamicParams.push(DynamicParam(dynamicParams_[0].slotPosition));
        data.intermediateOp = IntermediateOperation(
            Operations.SKIP,
            0,
            true
        );
    } 

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.
    function _totalAssets() internal view override returns (uint256) {
        bytes[2] memory dynamicValues;
        dynamicValues[0] = abi.encode(address(this));

        bytes memory res = _executeView(totalAssetsData[0], dynamicValues);
        return abi.decode(res, (uint256));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal override {
        bytes[2] memory dynamicValues;
        dynamicValues[0] = abi.encode(amount);

        _execute(depositData[0], dynamicValues);
    }

    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal override {
        bytes[2] memory dynamicValues;
        dynamicValues[0] = abi.encode(amount);

        _execute(withdrawData[0], dynamicValues);
    }

    // TODO support multiple operations
    function _execute(ExecutionData memory execData, bytes[2] memory dynamicValues) internal returns (bytes memory res) {        
        bytes memory t = _encodeContractCall(execData, dynamicValues);

        // execute to target
        bool succ;
        (succ, res) = address(execData.target).call(t);
        require(succ, 'Function call failed');

        return res;
    }

    // TODO support multiple operations
    function _executeView(ExecutionData memory execData, bytes[2] memory dynamicValues) internal view returns (bytes memory res) {
        bytes memory t = _encodeContractCall(execData, dynamicValues);

        // execute to target
        bool succ;
        (succ, res) = address(execData.target).staticcall(t);
        require(succ, 'Function call failed');

        return res;
    }

    function _encodeContractCall(ExecutionData memory execData, bytes[2] memory dynamicValues) internal pure returns (bytes memory encodedCalldata) {
        // encode and store dynamic params
        for(uint i=0; i<execData.dynamicParams.length; i++) {
            DynamicParam memory dynamicParam = execData.dynamicParams[i];
            execData.calldataParams[dynamicParam.slotPosition] = dynamicValues[i];
        }
       
        // pack it all together with sigs
        encodedCalldata = abi.encodePacked(encodedCalldata, execData.sig);
        for(uint i=0; i<execData.calldataParams.length; i++) {
            encodedCalldata = abi.encodePacked(encodedCalldata, execData.calldataParams[i]);
        }
    }
}
