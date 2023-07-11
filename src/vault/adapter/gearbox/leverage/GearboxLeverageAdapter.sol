// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {
    ERC20,
    IERC20,
    SafeERC20,
    AdapterBase,
    IERC20Metadata
} from "../../abstracts/AdapterBase.sol";
import { ICreditFacade, ICreditManagerV2 } from "../IGearbox.sol";
//import IERC721Upgradeable from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/IERC721Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC721/IERC721Upgradeable.sol";

contract GearboxLeverageAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    string internal _name;
    string internal _symbol;
    mapping(address => address) public creditAccounts;

    error WrongAsset();
    error InsufficientBalance();
    error NoOpenCreditAccount();
    error CreateAccountDisabled();

    /// @notice The Credit Facade Contract
    ICreditFacade public creditFacade;

    /// @notice The Credit Manager Contract
    ICreditManagerV2 public creditManager;

    /*//////////////////////////////////////////////////////////////
                                INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize a new Gearbox Passive Pool Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param addressProvider GearboxAddressProvider
     * @param gearboxInitData Encoded data for the Lido adapter initialization.
     * @dev `_pid` - The poolId for lpToken.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address addressProvider,
        bytes memory gearboxInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);
        uint256 _contractFacade = abi.decode(gearboxInitData, (address ));

        //initialize credit facade
        creditFacade = ICreditFacade(_contractFacade);
        creditManager = ICreditManagerV2(creditFacade.creditManager());

        if (asset() != creditFacade.underlying()) revert WrongAsset();

        _name = string.concat("VaultCraft GearboxCreditAccount ", " Adapter");
        _symbol = "vcGCA";

        IERC20(asset()).safeApprove(address(creditFacade), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                   DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/
    function minBorrowedAmount() public view returns(uint256) {
        (uint128 _minBorrowedAmount, ) = creditFacade.limits();
        return _minBorrowedAmount;
    }

    function maxBorrowedAmount() public view returns(uint256) {
        (, uint128 _maxBorrowedAmount) = creditFacade.limits();
        return _maxBorrowedAmount;
    }


    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/
    function _protocolDeposit(uint256 assets, uint256) internal override {
        ICreditFacade _creditFacade = creditFacade;
        //check that the underlying address is the same as that of the credit facade. else we may need to use the multicall option - done
        //check limits on the credit facade - how do we set these limits on first deposit given that we may not have anything to deposit
        //check that degen mode is enabled CreditFacade.whitelisted()
        //check that our account has the degen NFT using CreditFacade.degenNFT()
        //before deposit and withdrawa check if the address has opened a credit account
        //withdrawal of deposit means closing of credit account as gearbox provides no withdraw feature

        address degenNFT = _creditFacade.degenNFT();
        if(degenNFT == address (0))
            revert CreateAccountDisabled();

        uint nftBalance = IERC721Upgradeable(degenNFT).balanceOf(msg.sender);
        if(nftBalance == 0) revert InsufficientBalance();

        IERC20(asset()).safeApprove(address(creditManager), type(uint256).max);

        if(!_creditFacade.hasOpenedCreditAccount(msg.sender)){
            _creditFacade.openCreditAccount(
                assets,
                msg.sender,
                leverageFactor,
                0
            );
            return;
        }

        address depositToken = _creditFacade.underlying();
        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target : address (_creditFacade),
            callData : abi.encodeWithSelector(ICreditFacade.addCollateral.selector, msg.sender, depositToken, assets)
        });
        _creditFacade.multicall(calls);
    }

    function _protocolWithdraw(uint256 assets, uint256) internal override {
        // Sender has to send in all shares.
        // claim claimRewards()
        // closeAccount
        // transfer all amount to sender
        // take withdrawal fees if we need to

        if(!_creditFacade.hasOpenedCreditAccount(msg.sender)) revert NoOpenCreditAccount();

        MultiCall[] memory noCalls = new MultiCall[](0);
        creditFacade.closeCreditAccount(msg.sender, 0, false, noCalls);
    }



    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _name;
    }

    function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _symbol;
    }
}
