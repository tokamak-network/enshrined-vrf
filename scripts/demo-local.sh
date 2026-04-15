#!/usr/bin/env bash
# =============================================================================
# Enshrined VRF Local Demo
# =============================================================================
# Demonstrates the full VRF flow on a local Anvil chain:
#   1. Start Anvil
#   2. Deploy PredeployedVRF at the predeploy address
#   3. Deploy CoinFlip (randomness consumer)
#   4. Generate a VRF proof using Go enclave
#   5. Commit one randomness per block as DEPOSITOR_ACCOUNT
#   6. Call CoinFlip.flip() multiple times in the same block
#      — each gets unique randomness via keccak256(beta, callCounter)
#
# Usage: ./scripts/demo-local.sh
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTRACTS="$ROOT/contracts"

# ── Configuration ──
ANVIL_PORT=8545
RPC="http://localhost:$ANVIL_PORT"
DEPOSITOR="0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001"
VRF_ADDR="0x42000000000000000000000000000000000000f0"
# Test private key (RFC 9381 test vector — NEVER use in production)
SK="c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721"
# Anvil default deployer account (index 0)
DEPLOYER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

# Helper: mine a block
mine() {
    cast rpc evm_mine --rpc-url "$RPC" > /dev/null
}

echo "============================================"
echo "  Enshrined VRF — Local Demo"
echo "============================================"
echo ""

# ── Step 0: Build tools ──
echo "▸ Building vrf-prove CLI..."
(cd "$ROOT" && go build -o ./bin/vrf-prove ./vrf-enclave/cmd/vrf-prove/) 2>&1
echo "  ✓ Built"

# ── Step 1: Start Anvil ──
echo ""
echo "▸ Starting Anvil on port $ANVIL_PORT..."
anvil --port "$ANVIL_PORT" --silent &
ANVIL_PID=$!
trap "kill $ANVIL_PID 2>/dev/null; wait $ANVIL_PID 2>/dev/null" EXIT

# Wait for Anvil to be ready
for i in $(seq 1 30); do
    if cast chain-id --rpc-url "$RPC" &>/dev/null; then
        break
    fi
    sleep 0.1
done
echo "  ✓ Anvil running (PID=$ANVIL_PID)"

# ── Step 2: Deploy PredeployedVRF at predeploy address ──
echo ""
echo "▸ Deploying PredeployedVRF at $VRF_ADDR..."

# Build contracts
(cd "$CONTRACTS" && forge build --quiet)

# Get bytecode
BYTECODE=$(jq -r '.deployedBytecode.object' "$CONTRACTS/out/PredeployedVRF.sol/PredeployedVRF.json")

# Use anvil_setCode to place contract at predeploy address
cast rpc anvil_setCode "$VRF_ADDR" "$BYTECODE" --rpc-url "$RPC" > /dev/null
echo "  ✓ PredeployedVRF deployed at $VRF_ADDR"

# Verify
CODE_LEN=$(cast code "$VRF_ADDR" --rpc-url "$RPC" | wc -c)
echo "  ✓ Contract code length: $CODE_LEN bytes"

# ── Step 3: Deploy CoinFlip ──
echo ""
echo "▸ Deploying CoinFlip..."
COINFLIP_ADDR=$(forge create "$CONTRACTS/src/examples/CoinFlip.sol:CoinFlip" \
    --private-key "$DEPLOYER_KEY" \
    --rpc-url "$RPC" \
    --broadcast \
    --root "$CONTRACTS" \
    --json 2>/dev/null | jq -r '.deployedTo')
echo "  ✓ CoinFlip deployed at $COINFLIP_ADDR"

# ── Step 4: Set sequencer public key ──
echo ""
echo "▸ Setting sequencer public key..."
PK=$("$ROOT/bin/vrf-prove" -sk "$SK" -seed "0000000000000000000000000000000000000000000000000000000000000000" 2>/dev/null | grep "^pk=" | cut -d= -f2)
echo "  Public key: $PK"

# Impersonate depositor and fund it
cast rpc anvil_impersonateAccount "$DEPOSITOR" --rpc-url "$RPC" > /dev/null
cast rpc anvil_setBalance "$DEPOSITOR" "0x56BC75E2D63100000" --rpc-url "$RPC" > /dev/null  # 100 ETH
cast send "$VRF_ADDR" "setSequencerPublicKey(bytes)" "$PK" \
    --from "$DEPOSITOR" --rpc-url "$RPC" --unlocked > /dev/null 2>&1
echo "  ✓ Public key set"

# ── Step 5: Switch to manual mining ──
# From this point, we control block boundaries so that the commitment
# and all flip() calls land in the same block.
echo ""
echo "▸ Switching to manual mining mode..."
cast rpc evm_setAutomine false --rpc-url "$RPC" > /dev/null
echo "  ✓ Manual mining enabled"

# ── Step 6: Generate and commit VRF proof ──
echo ""
echo "============================================"
echo "  Generating & committing VRF randomness"
echo "============================================"
echo ""

# Next block will contain commitment + flips
BLOCK_NUM=$(cast block-number --rpc-url "$RPC")
NEXT_BLOCK=$((BLOCK_NUM + 1))
NONCE=0

# Compute seed = sha256(blockNumber || nonce)
BLOCK_HEX=$(printf '%064x' "$NEXT_BLOCK")
NONCE_HEX=$(printf '%064x' "$NONCE")
SEED=$(echo -n "${BLOCK_HEX}${NONCE_HEX}" | xxd -r -p | shasum -a 256 | cut -d' ' -f1)

# Generate VRF proof
PROOF_OUTPUT=$("$ROOT/bin/vrf-prove" -sk "$SK" -seed "$SEED")
BETA=$(echo "$PROOF_OUTPUT" | grep "^beta=" | cut -d= -f2)
PI=$(echo "$PROOF_OUTPUT" | grep "^pi=" | cut -d= -f2)

echo "  Block: $NEXT_BLOCK, Nonce: $NONCE"
echo "  seed = 0x${SEED:0:16}..."
echo "  beta = ${BETA:0:18}..."
echo ""

# Send commitment tx (stays in mempool until we mine)
# Get current nonce for the depositor (pending)
DEP_NONCE=$(cast nonce "$DEPOSITOR" --rpc-url "$RPC" 2>/dev/null)
cast send "$VRF_ADDR" \
    "commitRandomness(uint256,bytes32,bytes32,bytes)" \
    "$NONCE" "0x$SEED" "$BETA" "$PI" \
    --from "$DEPOSITOR" --rpc-url "$RPC" --unlocked --async \
    --nonce "$DEP_NONCE" > /dev/null 2>&1

echo "  ✓ Commitment tx in mempool"

# ── Step 7: Send flip() txs (all stay in mempool with explicit nonces) ──
echo ""
echo "▸ Sending 5 flip() transactions..."
DEPLOYER_ADDR=$(cast wallet address "$DEPLOYER_KEY" 2>/dev/null)
FLIP_NONCE=$(cast nonce "$DEPLOYER_ADDR" --rpc-url "$RPC" 2>/dev/null)
for i in 0 1 2 3 4; do
    TX_NONCE=$((FLIP_NONCE + i))
    cast send "$COINFLIP_ADDR" "flip()" \
        --private-key "$DEPLOYER_KEY" --rpc-url "$RPC" --async \
        --nonce "$TX_NONCE" > /dev/null 2>&1
done
echo "  ✓ 5 flip() txs in mempool"

# ── Step 8: Mine one block containing all 6 txs ──
echo ""
echo "▸ Mining block $NEXT_BLOCK (1 commitment + 5 flips)..."
mine
echo "  ✓ Block mined!"

# ── Step 9: Read results ──
echo ""
echo "============================================"
echo "  Results — 5 flips from 1 VRF commitment"
echo "============================================"
echo ""

echo "  ┌──────────┬────────┬────────────────────────────────────┐"
echo "  │  Call     │ Result │ Randomness                          │"
echo "  ├──────────┼────────┼────────────────────────────────────┤"

# Read the event logs from the block
BLOCK_HEX_RPC=$(printf '0x%x' "$NEXT_BLOCK")
LOGS=$(cast rpc eth_getLogs "{\"fromBlock\":\"$BLOCK_HEX_RPC\",\"toBlock\":\"$BLOCK_HEX_RPC\",\"address\":\"$COINFLIP_ADDR\"}" --rpc-url "$RPC" 2>/dev/null)

FLIP_COUNT=$(echo "$LOGS" | jq 'length')
for i in $(seq 0 $((FLIP_COUNT - 1))); do
    LOG_DATA=$(echo "$LOGS" | jq -r ".[$i].data")

    HEADS_HEX=$(echo "$LOG_DATA" | cut -c3-66)
    RANDOMNESS_HEX=$(echo "$LOG_DATA" | cut -c67-130)

    if [ "$HEADS_HEX" = "0000000000000000000000000000000000000000000000000000000000000001" ]; then
        RESULT="HEADS"
    else
        RESULT="TAILS"
    fi

    IDX=$((i + 1))
    printf "  │  flip #%d │ %-5s  │ 0x%.24s...  │\n" "$IDX" "$RESULT" "$RANDOMNESS_HEX"
done

echo "  └──────────┴────────┴────────────────────────────────────┘"
echo ""
echo "  Each flip() received a different randomness value,"
echo "  all derived from the same VRF beta: keccak256(beta, counter)"

# ── Step 10: Query final state ──
echo ""
echo "============================================"
echo "  Final contract state"
echo "============================================"
echo ""

# Switch back to auto-mine for queries
cast rpc evm_setAutomine true --rpc-url "$RPC" > /dev/null

COMMIT_NONCE=$(cast call "$VRF_ADDR" "commitNonce()" --rpc-url "$RPC" | cast to-dec 2>/dev/null || echo "?")
CALL_COUNTER=$(cast call "$VRF_ADDR" "callCounter()" --rpc-url "$RPC" | cast to-dec 2>/dev/null || echo "?")
SEQ_PK=$(cast call "$VRF_ADDR" "sequencerPublicKey()" --rpc-url "$RPC")

echo "  commitNonce:        $COMMIT_NONCE (total blocks with VRF)"
echo "  callCounter:        $CALL_COUNTER (calls derived from this block's beta)"
echo "  sequencerPublicKey: ${SEQ_PK:0:30}..."

# ── Step 11: Manual cast examples ──
echo ""
echo "============================================"
echo "  Try it yourself (Anvil still running)"
echo "============================================"
echo ""
echo "  # Query historical VRF proof (nonce 0):"
echo "  cast call $VRF_ADDR \"getResult(uint256)(bytes32,bytes32,bytes)\" 0 --rpc-url $RPC"
echo ""
echo "  # Verify the VRF output on-chain (via precompile at 0x0101 in production):"
echo "  # pk=$PK"
echo "  # seed=0x$SEED"
echo "  # beta=$BETA"
echo "  # pi=$PI"
echo ""
echo "  ✓ Demo complete!"
echo "    Press Ctrl+C to stop Anvil."
echo ""

# Keep Anvil running for manual experimentation
wait $ANVIL_PID
