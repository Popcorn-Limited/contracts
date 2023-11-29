#!/usr/bin/env bash

readonly ADMIN="0x2C3B135cd7dc6C673b358BEF214843DAb3464278"
readonly VCX="0xcE246eEa10988C495B4A90a905Ee9237a0f91543"
readonly WETH_VCX_LP="0x577A7f7EE659Aa14Dc16FD384B3F8078E23F1920"
readonly VE_VCX="0x0aB4bC35Ef33089B9082Ca7BB8657D7c4E819a1A"
readonly oVCX="0xaFa52E3860b4371ab9d8F08E801E9EA1027C0CA2"
readonly POP="0xD0Cd466b34A24fcB2f87676278AF2005Ca8A78c4"
readonly WETH="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
readonly BalancerPool="0x577A7f7EE659Aa14Dc16FD384B3F8078E23F1920"
readonly BalancerOracle="0xe2871224b413F55c5a2Fd21E49bD63A52e339b03"
readonly VaultRegistry="0x007318Dc89B314b47609C684260CfbfbcD412864"
readonly BoostV2="0xa2E88993a0f0dc6e6020431477f3A70c86109bBf"
readonly Minter="0x49f095B38eE6d8541758af51c509332e7793D4b0"
readonly TokenAdmin="0x03d103c547B43b5a76df7e652BD0Bb61bE0BD70d"
readonly VotingEscrow="0x0aB4bC35Ef33089B9082Ca7BB8657D7c4E819a1A"
readonly GaugeController="0xD57d8EEC36F0Ba7D8Fd693B9D97e02D8353EB1F4"
readonly GaugeFactory="0x32a33CC9dC61352E70cb557927E5F9544ddb0a26"
readonly SmartWalletChecker="0x8427155770f7e6b973249E2f9D140a495aBE4f90"
readonly VotingEscrowProxy="0x9B12C90BAd388B7e417271eb20678D1a7759507c"
readonly VotingEscrowDelegation="0xa2e88993a0f0dc6e6020431477f3a70c86109bbf"
readonly VaultRouter="0x8aed8Ea73044910760E8957B6c5b28Ac51f8f809"
readonly FeeRecipient="0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E"
readonly BalancerVault="0xba12222222228d8ba445958a75a0704d566bf2c8"
readonly VaultController="0x7D51BABA56C2CA79e15eEc9ECc4E92d9c0a7dbeb"
readonly VaultRegistry="0x007318Dc89B314b47609C684260CfbfbcD412864"

readonly PoolId="0x577a7f7ee659aa14dc16fd384b3f8078e23f1920000200000000000000000633"
readonly OracleMultiplier=7500
readonly OracleSecs=43200
readonly OracleAgo=0
readonly OracleMinPrice=100000000000000

echo "verifing deployed contract values"

echo "1. VCX:"
echo "1.1 Admin should be" $ADMIN
cast call $VCX "owner()"
echo "1.2 endOfMigrationTs should be 31.01.24"
cast call $VCX "endOfMigrationTs()"

echo "2. BalancerPool:"
echo "2.1 Assets should be" $VCX "and" $WETH
cast call $BalancerVault "getPoolTokens(bytes32)" $PoolId
echo "2.2 Weights should be 20 / 80"
cast call $BalancerPool "getNormalizedWeights()"
echo "2.3 Owner should be" $ADMIN
cast call $BalancerPool "getOwner()"

echo "3. BalancerOracle:"
echo "3.1 balancerTwapOracle should be" $BalancerPool
cast call $BalancerOracle "balancerTwapOracle()"
echo "3.2 Owner should be" $ADMIN
cast call $BalancerOracle "owner()"
echo "3.3 Multiplier should be" $OracleMultiplier
cast call $BalancerOracle "multiplier()"
echo "3.4 Secs should be" $OracleSecs
cast call $BalancerOracle "secs()"
echo "3.5 Ago should be" $OracleAgo
cast call $BalancerOracle "ago()"
echo "3.6 MinPrice should be" $OracleMinPrice
cast call $BalancerOracle "minPrice()"
echo "3.7 Price should be" $OracleMinPrice
cast call $BalancerOracle "getPrice()"

echo "4. OptionToken:"
echo "4.1 Oracle should be" $BalancerOracle
cast call $oVCX "oracle()"
echo "4.2 Owner should be" $ADMIN
cast call $oVCX "owner()"
echo "4.3 TokenAdmin should be" $TokenAdmin
cast call $oVCX "tokenAdmin()"
echo "4.4 paymentToken should be" $WETH
cast call $oVCX "paymentToken()"
echo "4.5 underlyingToken should be" $VCX
cast call $oVCX "underlyingToken()"
echo "4.6 treasury should be" $FeeRecipient
cast call $oVCX "treasury()"

echo "5. VotingEscrow:"
echo "5.1 TOKEN should be" $VCX
cast call $VE_VCX "TOKEN()"
echo "5.2 Owner should be" $ADMIN
cast call $VE_VCX "admin()"
echo "5.3 smart_wallet_checker should be" $SmartWalletChecker
cast call $VE_VCX "smart_wallet_checker()"

echo "6. BoostV2:"
echo "6.1 VE should be" $VE_VCX
cast call $BoostV2 "VE()"

echo "7. VotingEscrowProxy:"
echo "7.1 VOTING_ESCROW should be" $VE_VCX
cast call $VotingEscrowProxy "VOTING_ESCROW()"
echo "7.2 ownership_admin should be" $ADMIN
cast call $VotingEscrowProxy "ownership_admin()"
echo "7.2 emergency_admin should be" $ADMIN
cast call $VotingEscrowProxy "emergency_admin()"
echo "7.2 delegation should be" $VotingEscrowDelegation
cast call $VotingEscrowProxy "delegation()"

echo "8. VotingEscrowDelegation:"
echo "8.1 VOTING_ESCROW should be" $VE_VCX
cast call $VotingEscrowDelegation "VOTING_ESCROW()"
echo "8.2 Owner should be" $ADMIN
cast call $VotingEscrowDelegation "admin()"

echo "9. GaugeController:"
echo "9.1 VOTING_ESCROW should be" $VE_VCX
cast call $GaugeController "voting_escrow()"
echo "9.2 TOKEN should be" $BalancerPool
cast call $GaugeController "token()"
echo "9.3 Owner should be" $ADMIN
cast call $GaugeController "admin()"

echo "10. GaugeFactory:"
echo "10.1 popcornVaultRegistry should be" $VaultRegistry
cast call $GaugeFactory "popcornVaultRegistry()"
echo "10.2 gaugeImplementation should be ???"
cast call $GaugeFactory "getGaugeImplementation()"
echo "10.3 Owner should be" $ADMIN
cast call $GaugeFactory "owner()"
echo "10.4 gaugeAdmin should be" $ADMIN
cast call $GaugeFactory "gaugeAdmin()"

echo "11. TokenAdmin:"
echo "11.1 token should be" $oVCX
cast call $TokenAdmin "getToken()"
echo "11.2 minter should be" $Minter
cast call $TokenAdmin "minter()"
echo "11.3 Owner should be" $ADMIN
cast call $TokenAdmin "owner()"
echo "11.4 INITIAL_RATE should be 2M Token per week (in 1e18) '(2_000_000*1e18)/(86400 * 7)'"
cast call $TokenAdmin "INITIAL_RATE()"
echo "11.5 RATE_REDUCTION_TIME should be 91 days"
cast call $TokenAdmin "RATE_REDUCTION_TIME()"
echo "11.6 RATE_REDUCTION_COEFFICIENT should be 2.71% (in 1e18)"
cast call $TokenAdmin "RATE_REDUCTION_COEFFICIENT()"
echo "11.7 _miningEpoch should be 0"
cast call $TokenAdmin "getMiningEpoch()"
echo "11.8 _startEpochTime should be max uint256"
cast call $TokenAdmin "getStartEpochTime()"
echo "11.9 _startEpochSupply should be 0"
cast call $TokenAdmin "getStartEpochSupply()"
echo "11.10 _rate should be 0"
cast call $TokenAdmin "getInflationRate()"

echo "12. Minter:"
echo "12.1 token should be" $oVCX
cast call $Minter "getToken()"
echo "12.2 tokenAdmin should be" $TokenAdmin
cast call $Minter "getTokenAdmin()"
echo "12.3 _gaugeController should be" $GaugeController
cast call $Minter "getGaugeController()"