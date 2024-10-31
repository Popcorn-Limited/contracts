pragma solidity ^0.8.13;

import {Owned} from "src/utils/Owned.sol";
import {IPushOracle} from "src/interfaces/IPushOracle.sol";

contract PushOracleOwner is Owned {
    IPushOracle public oracle;

    address public keeper;

    event KeeperUpdated(address previous, address current);

    error NotKeeperNorOwner();

    constructor(address _oracle, address _owner) Owned(_owner) {
        oracle = IPushOracle(_oracle);
    }

    /*//////////////////////////////////////////////////////////////
                        SET PRICE LOGIC
    //////////////////////////////////////////////////////////////*/

    function setPrice(
        address base,
        address quote,
        uint256 bqPrice,
        uint256 qbPrice
    ) external onlyKeeperOrOwner {
        oracle.setPrice(base, quote, bqPrice, qbPrice);
    }

    function setPrices(
        address[] memory bases,
        address[] memory quotes,
        uint256[] memory bqPrices,
        uint256[] memory qbPrices
    ) external onlyKeeperOrOwner {
        oracle.setPrices(bases, quotes, bqPrices, qbPrices);
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

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
