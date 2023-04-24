#!/usr/bin/env bash

source .env && cast send 0x3Fcc4eA703054453D8697b58C5CB2585F8883C05 "notifyRewardAmount(address,uint256)" 0x6F0fecBC276de8fC69257065fE47C5a03d986394 	1250000000000000000000 --rpc-url $OPTIMISM_RPC_URL --private-key $PRIVATE_KEY --gas-limit 15000000