// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {ERC4626Upgradeable, IERC20Metadata, ERC20Upgradeable as ERC20, IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnedUpgradeable} from "../../utils/OwnedUpgradeable.sol";
import {VaultStorage} from "./VaultStorage.sol";

abstract contract AbstractBaseVaultStorage is
    ERC4626Upgradeable,
    PausableUpgradeable,
    OwnedUpgradeable,
    ReentrancyGuardUpgradeable,
    VaultStorage
{
    function __BaseVaultStorage_init(
        IERC20 asset_,
        address owner_,
        string memory name_,
        string memory symbol_
    ) internal initializer {
        __ERC4626_init(IERC20Metadata(address(asset_)));
        __Pausable_init();
        __ReentrancyGuard_init();
        __Owned_init(owner_);

        _name = name_;
        _symbol = symbol_;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                              LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    // TODO move this into a hook?
    /**
     * @notice Sets Deposit limit and min amount for deposits and withdrawals
     * @param depositLimit_ ...
     * @param minAmount_ ...
     */
    function setLimits(
        uint256 depositLimit_,
        uint256 minAmount_
    ) external onlyOwner {
        emit UpdatedLimits(depositLimit, depositLimit_, minAmount, minAmount_);

        depositLimit = depositLimit_;
        minAmount = minAmount_;
    }

    /*//////////////////////////////////////////////////////////////
                              PAUSE LOGIC
    //////////////////////////////////////////////////////////////*/

    function pause() external virtual onlyOwner {
        _pause();
    }

    function unpause() external virtual onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                    FULLFILLMENT INCENTIVE LOGIC
    //////////////////////////////////////////////////////////////*/

    // TODO move this into a hook for potentially dynamic fees?
    function setFullfillmentIncentive(
        uint256 fullfillmentIncentive_
    ) external onlyOwner {
        // TODO adjust threshold
        if (fullfillmentIncentive_ > 1e17)
            revert InvalidFee(fullfillmentIncentive_);

        emit UpdatedFullfillmentIncentive(
            fullfillmentIncentive,
            fullfillmentIncentive_
        );

        fullfillmentIncentive = fullfillmentIncentive_;
    }

    /*//////////////////////////////////////////////////////////////
                              FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    // TODO move this into a hook?
    function setFees(
        uint256 performanceFee_,
        uint256 managementFee_
    ) public onlyOwner {
        if (performanceFee_ > 2e17) revert InvalidFee(performanceFee_);
        if (managementFee_ > 1e17) revert InvalidFee(managementFee_);
        _takeFees();

        emit UpdatedFees(
            performanceFee,
            performanceFee_,
            managementFee,
            managementFee_
        );

        performanceFee = newPerformanceFee;
        managementFee = newManagementFee;
    }

    /*//////////////////////////////////////////////////////////////
                              MULTISIG LOGIC
    //////////////////////////////////////////////////////////////*/

    function addMultisig(
        address multisig,
        uint256 debtLimit,
        address oracle
    ) public onlyOwner {
        require(
            multisig != address(0) &&
                multisig != SENTINEL_MULTISIG &&
                multisig != address(this),
            "GS203"
        );
        require(multisigs[multisig] == address(0), "GS204");

        multisigs[multisig] = multisigs[SENTINEL_MULTISIG];
        multisigs[SENTINEL_MULTISIG] = multisig;

        debtInfo[multisig] = DebtInfo({
            debtLimit: debtLimit,
            currentDebt: 0,
            oracle: oracle,
            hwm: convertToAssets(10 ** decimals),
            hwmAfterFee: convertToAssets(10 ** decimals),
            lastUpdate: block.timestamp
        });
        multisigCount++;

        emit MultisigAdded(multisig, debtLimit);
    }

    function removeMultisig(
        address prevMultisig,
        address multisig
    ) public onlyOwner {
        require(
            multisig != address(0) && multisig != SENTINEL_MULTISIG,
            "GS203"
        );
        require(multisigs[prevMultisig] == multisig, "GS205");
        require(debtInfo[multisig].currentDebt == 0, "GS205");

        multisigs[prevMultisig] = multisigs[multisig];
        delete multisigs[multisig];
        delete debtInfo[multisig];
        multisigCount--;

        emit MultisigRemoved(multisig);
    }

    /**
     * @notice Replaces the multisig `oldOwner` in the Safe with `newOwner`.
     * @dev This can only be done via a Safe transaction.
     * @param prevMultisig Owner that pointed to the owner to be replaced in the linked list
     * @param oldMultisig Owner address to be replaced.
     * @param newMultisig New owner address.
     */
    function swapMultisig(
        address prevMultisig,
        address oldMultisig,
        address newMultisig,
        uint256 debtLimit,
        address oracle,
        uint256 securityDeposit
    ) public onlyOwner {
        // Owner address cannot be null, the sentinel or the Safe itself.
        require(
            newMultisig != address(0) &&
                newMultisig != SENTINEL_MULTISIG &&
                newMultisig != address(this),
            "GS203"
        );
        // No duplicate owners allowed.
        require(multisigs[newMultisig] == address(0), "GS204");
        // Validate oldOwner address and check that it corresponds to owner index.
        require(
            oldMultisig != address(0) && oldMultisig != SENTINEL_MULTISIG,
            "GS203"
        );
        require(multisigs[prevMultisig] == oldMultisig, "GS205");
        require(debtInfo[oldMultisig].currentDebt == 0, "GS205");

        multisigs[newMultisig] = multisigs[oldMultisig];
        multisigs[prevMultisig] = newMultisig;
        delete multisigs[oldMultisig];
        delete debtInfo[oldMultisig];

        debtInfo[newMultisig] = DebtInfo({
            debtLimit: debtLimit,
            currentDebt: 0,
            oracle: oracle,
            hwm: convertToAssets(10 ** decimals),
            hwmAfterFee: convertToAssets(10 ** decimals),
            lastUpdate: block.timestamp
        });

        emit RemovedMultisig(oldMultisig);
        emit AddedMultisig(newMultisig, debtLimit);
    }

     /**
     * @notice Returns if `multisig` is an owner of the Safe.
     * @return Boolean if multisig is an owner of the Safe.
     */
    function isMultisig(address multisig) public view returns (bool) {
        return
            multisig != SENTINEL_MULTISIG && multisigs[multisig] != address(0);
    }

    /**
     * @notice Returns a list of Safe owners.
     * @return Array of Safe owners.
     */
    function getMultisigs() public view returns (address[] memory) {
        address[] memory array = new address[](multisigCount);

        // populate return array
        uint256 index = 0;
        address currentMultisig = multisigs[SENTINEL_MULTISIG];
        while (currentMultisig != SENTINEL_MULTISIG) {
            array[index] = currentMultisig;
            currentMultisig = multisigs[currentMultisig];
            index++;
        }
        return array;
    }

    /*//////////////////////////////////////////////////////////////
                        OPERATOR LOGIC
    //////////////////////////////////////////////////////////////*/

    function setOperator(
        address operator,
        bool approved
    ) public virtual returns (bool success) {
        require(
            msg.sender != operator,
            "ERC7540Vault/cannot-set-self-as-operator"
        );
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        success = true;
    }

    function authorizeOperator(
        address controller,
        address operator,
        bool approved,
        bytes32 nonce,
        uint256 deadline,
        bytes memory signature
    ) public virtual returns (bool success) {
        require(
            controller != operator,
            "ERC7540Vault/cannot-set-self-as-operator"
        );
        require(block.timestamp <= deadline, "ERC7540Vault/expired");
        require(
            !authorizations[controller][nonce],
            "ERC7540Vault/authorization-used"
        );

        authorizations[controller][nonce] = true;

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        address recoveredAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256(
                                "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
                            ),
                            controller,
                            operator,
                            approved,
                            nonce,
                            deadline
                        )
                    )
                )
            ),
            v,
            r,
            s
        );

        require(
            recoveredAddress != address(0) && recoveredAddress == controller,
            "INVALID_SIGNER"
        );

        isOperator[controller][operator] = approved;

        emit OperatorSet(controller, operator, approved);

        success = true;
    }

    /*//////////////////////////////////////////////////////////////
                        GENERAL VIEWS
    //////////////////////////////////////////////////////////////*/

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

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(name())),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return
            block.chainid == INITIAL_CHAIN_ID
                ? INITIAL_DOMAIN_SEPARATOR
                : computeDomainSeparator();
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public pure virtual returns (bool) {
        return
            interfaceId == type(IERC4626).interfaceId ||
            interfaceId == type(IERC7540Operator).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
