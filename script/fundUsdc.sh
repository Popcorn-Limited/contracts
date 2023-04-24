#!/usr/bin/env bash

cast rpc anvil_impersonateAccount 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503 --rpc-url localhost:8545 && cast send 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 --rpc-url localhost:8545 \
--from 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503 \
  "transfer(address,uint256)(bool)" \
  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  100000000000