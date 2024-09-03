contract TestSafeGuard {
    constructor() {}

    // solhint-disallow-next-line payable-fallback
    fallback() external {
        // We don't revert on fallback to avoid issues in case of a Safe upgrade
        // E.g. The expected check method might change and then the Safe would be locked.
    }

    // function checkTransaction(
    //     address to,
    //     uint256 value,
    //     bytes memory data,
    //     Enum.Operation operation,
    //     uint256,
    //     uint256,
    //     uint256,
    //     address,
    //     // solhint-disallow-next-line no-unused-vars
    //     address payable,
    //     bytes memory,
    //     address
    // ) external view override {}

    // function checkAfterExecution(bytes32, bool) external view override {}
}
