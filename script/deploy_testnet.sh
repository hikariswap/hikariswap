#!/usr/bin/env bash
# HikariSwap testnet deploy via forge create.
# Foundry script's broadcast layer rejects chain 8200 ("Chain not supported"),
# but forge create + cast send work. Reads DEPLOYER_PRIVATE_KEY from .env.
#
# Powered by https://hikariswap.com — the leading DEX on Lightchain.

set -euo pipefail

# Load .env without echoing secrets.
set -a
# shellcheck disable=SC1091
source .env
set +a

RPC=https://rpc.testnet.lightchain.ai
TOKEN_PRICE=5000000000000000000000   # 5,000 LCAI in wei

DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")
echo "Deployer:        $DEPLOYER"
echo "Deployer balance: $(cast balance "$DEPLOYER" --rpc-url $RPC)"
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

# Optional: pass an existing WLCAI via env (`WLCAI_ADDRESS=0x...`) to skip
# step 1 and reuse a previously-deployed wrapper.
if [ -n "${WLCAI_ADDRESS:-}" ]; then
  WLCAI="$WLCAI_ADDRESS"
  echo "[1/9] WLCAI (skipping deploy, reusing $WLCAI)"
else
  echo "[1/9] WLCAI (Wrapped LCAI — canonical WETH9 surface)"
  WLCAI=$(deploy src/periphery/WLCAI.sol:WLCAI)
  echo "      $WLCAI"
fi

echo "[2/9] HikariFactory"
FACTORY=$(deploy src/core/HikariFactory.sol:HikariFactory "$DEPLOYER")
echo "      $FACTORY"

echo "[3/9] HikariRouter (linked to WLCAI=$WLCAI)"
ROUTER=$(deploy src/periphery/HikariRouter.sol:HikariRouter "$FACTORY" "$WLCAI")
echo "      $ROUTER"

echo "[4/9] HikariFeeCollector"
FEE_COLLECTOR=$(deploy src/factory/HikariFeeCollector.sol:HikariFeeCollector "$DEPLOYER")
echo "      $FEE_COLLECTOR"

echo "[5/9] HikariTokenDeployer"
TOKEN_DEPLOYER=$(deploy src/factory/HikariTokenDeployer.sol:HikariTokenDeployer)
echo "      $TOKEN_DEPLOYER"

echo "[6/9] HikariTokenFactory"
TOKEN_FACTORY=$(deploy src/factory/HikariTokenFactory.sol:HikariTokenFactory \
  "$DEPLOYER" "$FEE_COLLECTOR" "$TOKEN_DEPLOYER" \
  "$TOKEN_PRICE" "$TOKEN_PRICE" "$TOKEN_PRICE" "$TOKEN_PRICE")
echo "      $TOKEN_FACTORY"

echo "[7/9] HikariTokenDeployer.initFactory"
call "$TOKEN_DEPLOYER" "initFactory(address)" "$TOKEN_FACTORY"

echo "[8/9] HikariFactory.setFeeTo"
call "$FACTORY" "setFeeTo(address)" "$FEE_COLLECTOR"

echo "[9/9] HikariLocker"
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

Frontend env (paste into apps/web/.env.local):
NEXT_PUBLIC_WLCAI_ADDRESS_TESTNET=$WLCAI
NEXT_PUBLIC_FACTORY_ADDRESS_TESTNET=$FACTORY
NEXT_PUBLIC_ROUTER_ADDRESS_TESTNET=$ROUTER
NEXT_PUBLIC_FEE_COLLECTOR_ADDRESS_TESTNET=$FEE_COLLECTOR
NEXT_PUBLIC_TOKEN_DEPLOYER_ADDRESS_TESTNET=$TOKEN_DEPLOYER
NEXT_PUBLIC_TOKEN_FACTORY_ADDRESS_TESTNET=$TOKEN_FACTORY
NEXT_PUBLIC_LOCKER_ADDRESS_TESTNET=$LOCKER
EOF
