#!/usr/bin/env bash
# Verify deployed HikariSwap contracts on testnet.lightscan.app (Blockscout).

set -euo pipefail

VERIFIER_URL=https://testnet.lightscan.app/api/
CHAIN=8200

DEPLOYER=0xD6C0f5a2361CF061A7fbD336616c2eBA7973D9C9
WLCAI=0x4E31781fa4d3A7970B01d6b2C4357fDa6B6fE243
FACTORY=0xc9EbC8b387A56e4C44bFA89970A8cf5443b6F25C
ROUTER=0x9B5eeF08A6D7d796Dba00180935420c62D62D987
FEE_COLLECTOR=0x963040293C67b4A53E66E772ab9C11D71cdD84B1
TOKEN_DEPLOYER=0x7cF3c8Bf167dCFDd49E397aA27476470556A8b4a
TOKEN_FACTORY=0x0f4fFFd5864e41dB5f3aa8132e372e379FFe5f96
LOCKER=0x66e6878EAB57256336C6A87c4C322625aE9FCDe6

MIN_PRICE=0
TOKEN_PRICE=0

verify() {
  local addr="$1" path="$2" args="${3-}"
  local cmd=(forge verify-contract --chain "$CHAIN" --verifier blockscout --verifier-url "$VERIFIER_URL" --watch "$addr" "$path")
  if [ -n "$args" ]; then
    cmd+=(--constructor-args "$args")
  fi
  "${cmd[@]}"
}

echo "[1/7] WLCAI"
verify "$WLCAI" "src/periphery/WLCAI.sol:WLCAI"

echo "[2/7] HikariFactory"
verify "$FACTORY" "src/core/HikariFactory.sol:HikariFactory" \
  "$(cast abi-encode "constructor(address)" "$DEPLOYER")"

echo "[3/7] HikariRouter"
verify "$ROUTER" "src/periphery/HikariRouter.sol:HikariRouter" \
  "$(cast abi-encode "constructor(address,address)" "$FACTORY" "$WLCAI")"

echo "[4/7] HikariFeeCollector"
verify "$FEE_COLLECTOR" "src/factory/HikariFeeCollector.sol:HikariFeeCollector" \
  "$(cast abi-encode "constructor(address)" "$DEPLOYER")"

echo "[5/7] HikariTokenDeployer"
verify "$TOKEN_DEPLOYER" "src/factory/HikariTokenDeployer.sol:HikariTokenDeployer"

echo "[6/7] HikariTokenFactory"
verify "$TOKEN_FACTORY" "src/factory/HikariTokenFactory.sol:HikariTokenFactory" \
  "$(cast abi-encode "constructor(address,address,address,uint256,uint256,uint256,uint256,uint256)" \
    "$DEPLOYER" "$FEE_COLLECTOR" "$TOKEN_DEPLOYER" \
    "$MIN_PRICE" "$TOKEN_PRICE" "$TOKEN_PRICE" "$TOKEN_PRICE" "$TOKEN_PRICE")"

echo "[7/7] HikariLocker"
verify "$LOCKER" "src/locker/HikariLocker.sol:HikariLocker"

echo
echo "All verifications submitted."
