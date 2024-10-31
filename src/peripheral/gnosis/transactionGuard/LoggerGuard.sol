import {DebugTransactionGuard} from "safe-smart-account/examples/guards/DebugTransactionGuard.sol";

/**
 * @title   LoggerGuard
 * @author  RedVeil
 * @notice  Test transaction guard that logs all transactions
 */
contract LoggerGuard is DebugTransactionGuard {}