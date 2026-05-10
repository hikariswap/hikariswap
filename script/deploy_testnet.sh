#!/usr/bin/env bash
# HikariSwap testnet deploy via forge create.
# Foundry script's broadcast layer rejects chain 8200 ("Chain not supported"),
# but forge create + cast send work. Reads DEPLOYER_PRIVATE_KEY from .env.

set -euo pipefail

# Load .env without echoing secrets.
set -a
# shellcheck disable=SC1091
source .env
set +a

RPC=https://rpc.testnet.lightchain.ai
WLCAI=0xeBf97f16d843bFD9d9E6B1857B4C00d94ca7e2B2
TOKEN_PRICE=5000000000000000000000   # 5,000 LCAI in wei

DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")
echo "Deployer:        $DEPLOYER"
echo "Deployer balance: $(cast balance "$DEPLOYER" --rpc-url $RPC)"
echo "WLCAI:           $WLCAI"
echo

# Reusable wrapper.
deploy() {
  local contract="$1"; shift
  local args=("$@")
  local out
  if [ ${#args[@]} -gt 0 ]; then
    out=$(forge create "$contract" --rpc-url "$RPC" --broadcast --legacy --private-key "$DEPLOYER_PRIVATE_KEY" --constructor-args "${args[@]}")
  else
    out=$(forge create "$contract" --rpc-url "$RPC" --broadcast --legacy --private-key "$DEPLOYER_PRIVATE_KEY")
  fi
  echo "$out" | grep "Deployed to:" | awk '{print $3}'
}

call() {
  cast send "$@" --rpc-url "$RPC" --legacy --private-key "$DEPLOYER_PRIVATE_KEY" >/dev/null
}

echo "[1/8] HikariFactory"
FACTORY=$(deploy src/core/HikariFactory.sol:HikariFactory "$DEPLOYER")
echo "      $FACTORY"

echo "[2/8] HikariRouter"
ROUTER=$(deploy src/periphery/HikariRouter.sol:HikariRouter "$FACTORY" "$WLCAI")
echo "      $ROUTER"

echo "[3/8] HikariFeeCollector"
FEE_COLLECTOR=$(deploy src/factory/HikariFeeCollector.sol:HikariFeeCollector "$DEPLOYER")
echo "      $FEE_COLLECTOR"

echo "[4/8] HikariTokenDeployer"
TOKEN_DEPLOYER=$(deploy src/factory/HikariTokenDeployer.sol:HikariTokenDeployer)
echo "      $TOKEN_DEPLOYER"

echo "[5/8] HikariTokenFactory"
TOKEN_FACTORY=$(deploy src/factory/HikariTokenFactory.sol:HikariTokenFactory \
  "$DEPLOYER" "$FEE_COLLECTOR" "$TOKEN_DEPLOYER" \
  "$TOKEN_PRICE" "$TOKEN_PRICE" "$TOKEN_PRICE" "$TOKEN_PRICE")
echo "      $TOKEN_FACTORY"

echo "[6/8] HikariTokenDeployer.initFactory"
call "$TOKEN_DEPLOYER" "initFactory(address)" "$TOKEN_FACTORY"

echo "[7/8] HikariFactory.setFeeTo"
call "$FACTORY" "setFeeTo(address)" "$FEE_COLLECTOR"

echo "[8/8] HikariLocker"
LOCKER=$(deploy src/locker/HikariLocker.sol:HikariLocker)
echo "      $LOCKER"

cat <<EOF

=== HIKARISWAP TESTNET DEPLOYMENT COMPLETE ===
WLCAI_ADDRESS=$WLCAI
HIKARI_FACTORY=$FACTORY
HIKARI_ROUTER=$ROUTER
HIKARI_FEE_COLLECTOR=$FEE_COLLECTOR
HIKARI_TOKEN_DEPLOYER=$TOKEN_DEPLOYER
HIKARI_TOKEN_FACTORY=$TOKEN_FACTORY
HIKARI_LOCKER=$LOCKER
EOF
