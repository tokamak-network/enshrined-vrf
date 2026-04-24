#!/usr/bin/env bash
# =============================================================================
# Enshrined VRF — Local auto-commit sequencer daemon
# =============================================================================
# Every tick:
#   1. Compute seed = sha256(nextBlock || commitNonce)
#   2. Generate ECVRF proof via ./bin/vrf-prove
#   3. Submit commitRandomness tx as DEPOSITOR_ACCOUNT (async → mempool)
#   4. Mine a block via evm_mine (bundles commit + any pending user txs)
#
# Assumes:
#   - Anvil is running at $RPC with automine OFF
#   - EnshrainedVRF is deployed at $VRF_ADDR
#   - DEPOSITOR is impersonated and funded
#   - Sequencer public key has already been set
#
# Usage:  scripts/vrf-sequencer.sh
# =============================================================================

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

RPC="${RPC:-http://localhost:8545}"
DEPOSITOR="${DEPOSITOR:-0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001}"
VRF_ADDR="${VRF_ADDR:-0x42000000000000000000000000000000000000f0}"
# RFC 9381 test-vector sk — local dev only, NEVER production.
SK="${VRF_SK:-c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721}"
INTERVAL="${INTERVAL:-1}"

VRF_PROVE="$ROOT/bin/vrf-prove"
if [ ! -x "$VRF_PROVE" ]; then
    echo "[seq] building vrf-prove..."
    (cd "$ROOT" && go build -o ./bin/vrf-prove ./vrf-enclave/cmd/vrf-prove/) || {
        echo "[seq] FATAL: could not build vrf-prove" >&2; exit 1;
    }
fi

tick() {
    local block_num next_block nonce seed proof beta pi dep_nonce
    block_num=$(cast block-number --rpc-url "$RPC") || return 1
    next_block=$((block_num + 1))
    nonce=$(cast call "$VRF_ADDR" "commitNonce()" --rpc-url "$RPC" | cast to-dec) || return 1

    local block_hex nonce_hex
    block_hex=$(printf '%064x' "$next_block")
    nonce_hex=$(printf '%064x' "$nonce")
    seed=$(printf '%s%s' "$block_hex" "$nonce_hex" | xxd -r -p | shasum -a 256 | cut -d' ' -f1)

    proof=$("$VRF_PROVE" -sk "$SK" -seed "$seed" 2>/dev/null) || return 1
    beta=$(echo "$proof" | grep "^beta=" | cut -d= -f2)
    pi=$(echo "$proof"   | grep "^pi="   | cut -d= -f2)

    dep_nonce=$(cast nonce "$DEPOSITOR" --rpc-url "$RPC") || return 1
    # Bump the commit's priority fee high so Anvil orders it first in the block.
    # User txs at default gas price land after the commit — getRandomness() then sees _currentBlock.
    cast send "$VRF_ADDR" \
        "commitRandomness(uint256,bytes32,bytes32,bytes)" \
        "$nonce" "0x$seed" "$beta" "$pi" \
        --from "$DEPOSITOR" --rpc-url "$RPC" --unlocked --async \
        --nonce "$dep_nonce" \
        --priority-gas-price 100000000000 \
        --gas-price         100000000000 > /dev/null 2>&1 || return 1

    cast rpc evm_mine --rpc-url "$RPC" > /dev/null 2>&1 || return 1
    printf '[seq] block=%s nonce=%s beta=%s...\n' "$next_block" "$nonce" "${beta:0:18}"
}

echo "[seq] VRF auto-commit daemon — interval=${INTERVAL}s rpc=$RPC"
trap 'echo "[seq] shutting down"; exit 0' INT TERM

while :; do
    tick || echo "[seq] tick failed (will retry)"
    sleep "$INTERVAL"
done
