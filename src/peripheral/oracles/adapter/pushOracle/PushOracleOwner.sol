pragma solidity ^0.8.13;

import {Owned} from "src/utils/Owned.sol";

interface IPushOracle {
    function setPrice(
        address base,
        address quote,
        uint256 bqPrice,
        uint256 qbPrice
    ) external;
}

contract PushOracleOwner is Owned {
    IPushOracle public oracle;

    address public keeper;

    event KeeperUpdated(address previous, address current);

    error NotKeeperNorOwner();

    constructor(address _oracle, address _owner) Owned(_owner) {
        oracle = IPushOracle(_oracle);
    }

    function setPrice(
        address base,
        address quote,
        uint256 bqPrice,
        uint256 qbPrice
    ) external onlyKeeperOrOwner {
        oracle.setPrice(base, quote, bqPrice, qbPrice);
    }

    function setKeeper(address _keeper) external onlyOwner {
        emit KeeperUpdated(keeper, _keeper);
        keeper = _keeper;
    }

    function acceptOracleOwnership() external onlyOwner {
        Owned(address(oracle)).acceptOwnership();
    }

    modifier onlyKeeperOrOwner() {
        if (msg.sender != owner && msg.sender != keeper)
            revert NotKeeperNorOwner();
        _;
    }
}
