// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IVaultFactoryV2 {
    function createNewMarket(
        uint256 fee,
        address token,
        address depeg,
        uint256 beginEpoch,
        uint256 endEpoch,
        address oracle,
        string memory name
    ) external returns (address);

    function treasury() external view returns (address);

    function getVaults(uint256) external view returns (address[2] memory);

    function getEpochFee(uint256) external view returns (uint16);

    function marketToOracle(uint256 _marketId) external view returns (address);

    function transferOwnership(address newOwner) external;

    function changeTimelocker(address newTimelocker) external;

    function marketIdToVaults(uint256 _marketId)
    external
    view
    returns (address[2] memory);
}

interface ICarousel {
    // function name() external view  returns (string memory);
    // function symbol() external view  returns (string memory);
    function asset() external view  returns (address);

    function token() external view returns (address);

    function strike() external view returns (uint256);

    function controller() external view returns (address);

    function counterPartyVault() external view returns (address);

    function getEpochConfig(uint256) external view returns (uint40, uint40, uint40);

    function totalAssets(uint256) external view returns (uint256);

    function epochExists(uint256 _id) external view returns (bool);

    function epochResolved(uint256 _id) external view returns (bool);

    function finalTVL(uint256 _id) external view returns (uint256);

    function claimTVL(uint256 _id) external view returns (uint256);

    function setEpoch(
        uint40 _epochBegin,
        uint40 _epochEnd,
        uint256 _epochId
    ) external;

    function deposit(
        uint256 id,
        uint256 amount,
        address receiver
    ) external;

    function resolveEpoch(uint256 _id) external;

    function setClaimTVL(uint256 _id, uint256 _amount) external;

    function changeController(address _controller) external;

    function sendTokens(
        uint256 _id,
        uint256 _amount,
        address _receiver
    ) external;

    function whiteListAddress(address _treasury) external;

    function setCounterPartyVault(address _counterPartyVault) external;

    function setEpochNull(uint256 _id) external;

    function whitelistedAddresses(address _address)
    external
    view
    returns (bool);

    function enListInRollover(
        uint256 _assets,
        uint256 _epochId,
        address _receiver
    ) external;

    function deListInRollover(address _receiver) external;

    function mintDepositInQueue(uint256 _epochId, uint256 _operations) external;

    function mintRollovers(uint256 _epochId, uint256 _operations) external;

    function setEmissions(uint256 _epochId, uint256 _emissionsRate) external;

    function previewEmissionsWithdraw(uint256 _id, uint256 _assets) external;

    function changeRelayerFee(uint256 _relayerFee) external;

    function changeDepositFee(uint256 _depositFee) external;

    function changeTreasury(address) external;

    function balanceOfEmissoins(address _user, uint256 _epochId)
    external
    view
    returns (uint256);

    function emissionsToken() external view returns (address);

    function relayerFee() external view returns (uint256);

    function depositFee() external view returns (uint256);

    function emissions(uint256 _epochId) external view returns (uint256);

    function cleanupRolloverQueue(address[] memory) external;

    function getDepositQueueLength() external view returns (uint256);

    function getRolloverQueueLength() external view returns (uint256);

    function getRolloverTVL() external view returns (uint256);

    function getDepositQueueTVL() external view returns (uint256);

    function getAllEpochs() external view returns (uint256[] memory);

    function rolloverAccounting(uint256 _epochId)
    external
    view
    returns (uint256);
}

interface IMarketRegistry {
    function getMarketId(/*some_param*/) external view returns (uint256);
}

