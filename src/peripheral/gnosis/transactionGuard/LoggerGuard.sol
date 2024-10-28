import {DebugTransactionGuard, Enum} from "safe-smart-account/examples/guards/DebugTransactionGuard.sol";

contract LoggerGuard is DebugTransactionGuard {
    event ModuleTransactionDetails(
        address indexed safe,
        address to,
        uint256 value,
        bytes data,
        Enum.Operation operation,
        address module
    );

    event ModuleExecutionDetails(bytes32 indexed txHash, bool success);

    function checkModuleTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        address module
    ) external view {
        emit ModuleTransactionDetails(
            msg.sender,
            to,
            value,
            data,
            operation,
            module
        );
    }

    function checkAfterModuleExecution(
        bytes32 txHash,
        bool success
    ) external view {
        emit ModuleExecutionDetails(txHash, success);
    }
}
