// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20 } from "../../abstracts/AdapterBase.sol";
import { IPoolService, IContractRegistry, IAddressProvider } from "../IGearbox.sol";

/**
 * @title   Gearbox Passive Pool Adapter
 * @author  RedVeil
 * @notice  ERC4626 wrapper for Gearbox's passive pools.
 *
 * An ERC4626 compliant Wrapper for https://github.com/Gearbox-protocol/core-v2/blob/main/contracts/pool/PoolService.sol.
 * Allows wrapping Passive pools.
 */
contract GearboxPassivePoolAdapter is AdapterBase {
  using SafeERC20 for IERC20;

  string internal _name;
  string internal _symbol;

  /// @notice The Pool Service Contract
  IPoolService public poolService;

  /// @notice The Diesel Token Contract
  IERC20 public dieselToken;

  /*//////////////////////////////////////////////////////////////
                                INITIALIZATION
   //////////////////////////////////////////////////////////////*/

  error WrongPool();

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

    uint256 _pid = abi.decode(gearboxInitData, (uint256));

    poolService = IPoolService(IContractRegistry(IAddressProvider(addressProvider).getContractsRegister()).pools(_pid));
    dieselToken = IERC20(poolService.dieselToken());

    if (asset() != poolService.underlyingToken()) revert WrongPool();

    _name = string.concat("VaultCraft GearboxPassivePool ", IERC20Metadata(asset()).name(), " Adapter");
    _symbol = string.concat("vcGPP-", IERC20Metadata(asset()).symbol());

    IERC20(asset()).safeApprove(address(poolService), type(uint256).max);
  }

  function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
    return _name;
  }

  function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
    return _symbol;
  }

  /*//////////////////////////////////////////////////////////////
                          ACCOUNTING LOGIC
  //////////////////////////////////////////////////////////////*/

  /// @dev Calculate totalAssets by converting the total diesel tokens to underlying amount
    function _totalAssets() internal view override returns (uint256) {
    uint256 _totalDieselTokens = dieselToken.balanceOf(address(this));

    // roundUp to account for fromDiesel() ReoundDown
    return _totalDieselTokens == 0 ? 0 : poolService.fromDiesel(_totalDieselTokens);
  }

  /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LIMIT LOGIC
  //////////////////////////////////////////////////////////////*/

  function maxDeposit(address) public view override returns (uint256) {
    if (paused() || poolService.paused()) return 0;

    return poolService.expectedLiquidityLimit() - poolService.expectedLiquidity();
  }

  function maxMint(address) public view override returns (uint256) {
    if (paused() || poolService.paused()) return 0;

    return convertToShares(poolService.expectedLiquidityLimit() - poolService.expectedLiquidity());
  }

  /// @dev When poolService is paused and we didnt withdraw before (paused()) return 0
  function maxWithdraw(address owner) public view override returns (uint256) {
    if (poolService.paused() && !paused()) return 0;

    return convertToAssets(balanceOf(owner));
  }

  /// @dev When poolService is paused and we didnt withdraw before (paused()) return 0
  function maxRedeem(address owner) public view override returns (uint256) {
    if (poolService.paused() && !paused()) return 0;

    return balanceOf(owner);
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

  function _protocolDeposit(uint256 assets, uint256) internal override {
    poolService.addLiquidity(assets, address(this), 0);
  }

  function _protocolWithdraw(uint256 assets, uint256) internal override {
    // Added +1 to account for withdraw roundDown case
    poolService.removeLiquidity(poolService.toDiesel(assets) + 1, address(this));
  }
}
