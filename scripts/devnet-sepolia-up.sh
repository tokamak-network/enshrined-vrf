#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY_AFTER_START="${VERIFY_AFTER_START:-1}"

echo "[up] preflight"
"$ROOT/scripts/devnet-sepolia-preflight.sh"

echo
echo "[up] prepare"
"$ROOT/scripts/devnet-sepolia-prepare.sh"

echo
echo "[up] start"
"$ROOT/scripts/devnet-sepolia-start.sh"

if [ "$VERIFY_AFTER_START" = "1" ]; then
  echo
  echo "[up] verify randomness"
  "$ROOT/scripts/devnet-sepolia-verify-random.sh"
else
  echo
  echo "[up] skipping verify because VERIFY_AFTER_START=$VERIFY_AFTER_START"
  echo "Run ./scripts/devnet-sepolia-verify-random.sh when the L2 is ready."
fi
