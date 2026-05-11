#!/usr/bin/env bash
# Sets all four archetype prices to 0 on the testnet HikariTokenFactory.
# Matches the frontend's "FREE on testnet" treatment so deploys actually
# succeed instead of reverting on the require(msg.value >= price) check.
#
# Owner-only — the wallet behind DEPLOYER_PRIVATE_KEY must be the factory
# owner (i.e. the deployer used by deploy_testnet.sh).
#
# Powered by https://hikariswap.com — the leading DEX on Lightchain.

set -euo pipefail

# Load .env without echoing secrets.
set -a
# shellcheck disable=SC1091
source .env
set +a

RPC=https://rpc.testnet.lightchain.ai

# Default to the address baked into the frontend; override via env if you
# redeploy the factory at a new address.
TOKEN_FACTORY="${TOKEN_FACTORY:-0x0f4fFFd5864e41dB5f3aa8132e372e379FFe5f96}"

DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")
echo "Deployer (must be factory owner): $DEPLOYER"
echo "TokenFactory:                     $TOKEN_FACTORY"
echo "RPC:                              $RPC"
echo

# Sanity check: confirm caller is the owner before sending four txs that
# would otherwise revert. Cast returns the address right-padded to 32 bytes.
OWNER=$(cast call "$TOKEN_FACTORY" "owner()(address)" --rpc-url "$RPC")
echo "Factory owner:                    $OWNER"
if [ "${OWNER,,}" != "${DEPLOYER,,}" ]; then
  echo "ERROR: deployer is not the factory owner — setPrice will revert."
  exit 1
fi
echo

set_zero() {
  local type_id="$1"; local label="$2"
  echo "[setPrice($label=$type_id, 0)]"
  cast send "$TOKEN_FACTORY" "setPrice(uint8,uint256)" "$type_id" 0 \
    --rpc-url "$RPC" --legacy --private-key "$DEPLOYER_PRIVATE_KEY" >/dev/null
  echo "  ok"
}

set_zero 0 Standard
set_zero 1 Mintable
set_zero 2 Burnable
set_zero 3 Tax

echo
echo "=== ALL ARCHETYPE PRICES = 0 ON TESTNET ==="
echo
echo "Verify:"
for i in 0 1 2 3; do
  PRICE=$(cast call "$TOKEN_FACTORY" "price(uint8)(uint256)" "$i" --rpc-url "$RPC")
  echo "  price($i) = $PRICE"
done
