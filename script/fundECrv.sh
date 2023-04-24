#!/usr/bin/env bash

cast rpc anvil_impersonateAccount 0x82a7E64cdCaEdc0220D0a4eB49fDc2Fe8230087A --rpc-url localhost:8545 && cast send 0x06325440D014e39736583c165C2963BA99fAf14E --rpc-url localhost:8545 \
--from 0x82a7E64cdCaEdc0220D0a4eB49fDc2Fe8230087A \
  "transfer(address,uint256)(bool)" \
  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  100000000000000000000