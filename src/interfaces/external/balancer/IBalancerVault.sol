pragma solidity ^0.8.15;

enum SwapKind {
    GIVEN_IN,
    GIVEN_OUT
}

struct BatchSwapStep {
    bytes32 poolId;
    uint256 assetInIndex;
    uint256 assetOutIndex;
    uint256 amount;
    bytes userData;
}

interface IAsset {}

struct FundManagement {
    address sender;
    bool fromInternalBalancer;
    address payable recipient;
    bool toInternalBalance;
}

struct JoinPoolRequest {
    IAsset[] assets;
    uint256[] maxAmountsIn;
    bytes userData;
    bool fromInternalBalance;
}

interface IBalancerVault {
    function batchSwap(
        SwapKind _kind,
        BatchSwapStep[] memory _swaps,
        IAsset[] memory _assets,
        FundManagement memory _funds,
        int256[] memory _limits,
        uint256 deadline
    ) external returns (int256[] memory assetDeltas);
}
