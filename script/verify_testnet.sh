#!/usr/bin/env bash
# Verify deployed HikariSwap contracts on testnet.lightscan.app (Blockscout).

set -euo pipefail

VERIFIER_URL=https://testnet.lightscan.app/api/
CHAIN=8200

DEPLOYER=0xD6C0f5a2361CF061A7fbD336616c2eBA7973D9C9
WLCAI=0xeBf97f16d843bFD9d9E6B1857B4C00d94ca7e2B2
FACTORY=0x5f4f2076dbada2D8335854DFcff9D493f2e69EaE
ROUTER=0xF90CbB10099898e47c389550F3A5d4dD145a0794
FEE_COLLECTOR=0xbf357c921fD7dc02F536C949E01906113De339A4
TOKEN_DEPLOYER=0x698Df75AE72985f846CB00C73a26c8C1425e019c
TOKEN_FACTORY=0x76D3bf0AD6855302077818115c4295fA4c2B0302
LOCKER=0xb1Ba9C9a6f6E80CFDB7bf2F77C630DC420c3A558

TOKEN_PRICE=5000000000000000000000

verify() {
  local addr="$1" path="$2" args="${3-}"
  local cmd=(forge verify-contract --chain "$CHAIN" --verifier blockscout --verifier-url "$VERIFIER_URL" --watch "$addr" "$path")
  if [ -n "$args" ]; then
    cmd+=(--constructor-args "$args")
  fi
  "${cmd[@]}"
}

echo "[1/6] HikariFactory"
verify "$FACTORY" "src/core/HikariFactory.sol:HikariFactory" \
  "$(cast abi-encode "constructor(address)" "$DEPLOYER")"

echo "[2/6] HikariRouter"
verify "$ROUTER" "src/periphery/HikariRouter.sol:HikariRouter" \
  "$(cast abi-encode "constructor(address,address)" "$FACTORY" "$WLCAI")"

echo "[3/6] HikariFeeCollector"
verify "$FEE_COLLECTOR" "src/factory/HikariFeeCollector.sol:HikariFeeCollector" \
  "$(cast abi-encode "constructor(address)" "$DEPLOYER")"

echo "[4/6] HikariTokenDeployer"
verify "$TOKEN_DEPLOYER" "src/factory/HikariTokenDeployer.sol:HikariTokenDeployer"

echo "[5/6] HikariTokenFactory"
verify "$TOKEN_FACTORY" "src/factory/HikariTokenFactory.sol:HikariTokenFactory" \
  "$(cast abi-encode "constructor(address,address,address,uint256,uint256,uint256,uint256)" \
    "$DEPLOYER" "$FEE_COLLECTOR" "$TOKEN_DEPLOYER" \
    "$TOKEN_PRICE" "$TOKEN_PRICE" "$TOKEN_PRICE" "$TOKEN_PRICE")"

echo "[6/6] HikariLocker (already verified — re-running is idempotent)"
verify "$LOCKER" "src/locker/HikariLocker.sol:HikariLocker"

echo
echo "All verifications submitted."
