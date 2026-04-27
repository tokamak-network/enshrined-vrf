#!/usr/bin/env bash
# =============================================================================
# Enshrined VRF — Arcade (one-shot local demo)
# =============================================================================
# 1. Start Anvil (automine OFF)
# 2. Deploy EnshrainedVRF at predeploy address + set sequencer public key
# 3. Deploy CoinFlip / DiceRoll / Plinko / Lottery
# 4. Start the VRF auto-commit sequencer daemon (1 block / sec)
# 5. Write arcade/shared/config.js with deployed addresses
# 6. Serve arcade/ over HTTP, print MetaMask setup, and park until Ctrl-C.
#
# Usage: ./scripts/arcade.sh
# =============================================================================

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTRACTS="$ROOT/contracts"
ARCADE="$ROOT/arcade"

ANVIL_PORT="${ANVIL_PORT:-8545}"
HTTP_PORT="${HTTP_PORT:-5173}"
RPC="http://localhost:$ANVIL_PORT"
DEPOSITOR="0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001"
VRF_ADDR="0x42000000000000000000000000000000000000f0"
SK="c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721"
DEPLOYER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

export RPC VRF_ADDR DEPOSITOR VRF_SK="$SK" INTERVAL="${INTERVAL:-1}"

PIDS=()
# Recursively collect all descendants of a PID (children, grandchildren, …).
descendants() {
    local pid=$1 kids kid
    kids=$(pgrep -P "$pid" 2>/dev/null) || return 0
    for kid in $kids; do
        echo "$kid"
        descendants "$kid"
    done
}
cleanup() {
    # Prevent trap re-entry if the user mashes Ctrl-C.
    trap - INT TERM EXIT
    echo ""
    echo "▸ stopping background processes"
    # Gather the full descendant tree BEFORE killing (once a parent dies,
    # pgrep can no longer walk to its children).
    local all_pids
    all_pids=$(descendants $$)
    # Polite SIGTERM first — gives anvil/python a chance to flush.
    [ -n "$all_pids" ] && kill -TERM $all_pids 2>/dev/null
    sleep 0.3
    # Force-kill anything still breathing.
    local survivors
    survivors=$(descendants $$)
    [ -n "$survivors" ] && kill -KILL $survivors 2>/dev/null
    exit 0
}
trap cleanup INT TERM

log()  { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*" >&2; }

echo "========================================================"
echo "   Enshrined VRF Arcade — local demo"
echo "========================================================"

# ── 0. tooling checks ──
for bin in anvil cast forge jq shasum; do
    command -v "$bin" >/dev/null || { warn "missing tool: $bin"; exit 1; }
done

# ── 1. build vrf-prove ──
log "building vrf-prove CLI"
(cd "$ROOT" && go build -o ./bin/vrf-prove ./vrf-enclave/cmd/vrf-prove/) >/dev/null
ok "built $ROOT/bin/vrf-prove"

# ── 2. build contracts ──
log "compiling contracts"
(cd "$CONTRACTS" && forge build --quiet)
ok "contracts built"

# ── 3. launch anvil ──
log "starting Anvil on port $ANVIL_PORT"
# Chain ID 31337 = Anvil/Hardhat default. Avoid quirky IDs (e.g. 13374 collides
# with GoChain Testnet on chainid.network, which makes MetaMask warn the user).
anvil --port "$ANVIL_PORT" --silent \
      --chain-id 31337 \
      --block-time 999999 \
      --block-base-fee-per-gas 0 \
      --order fees &
PIDS+=($!)
for _ in $(seq 1 40); do
    cast chain-id --rpc-url "$RPC" >/dev/null 2>&1 && break
    sleep 0.1
done
cast chain-id --rpc-url "$RPC" >/dev/null || { warn "anvil failed to start"; exit 1; }
cast rpc evm_setAutomine false --rpc-url "$RPC" >/dev/null
ok "Anvil up (automine OFF)"

# ── 4. set up EnshrainedVRF predeploy ──
log "installing ArcadeVRF (demo-relaxed predeploy) at $VRF_ADDR"
BYTECODE=$(jq -r '.deployedBytecode.object' "$CONTRACTS/out/ArcadeVRF.sol/ArcadeVRF.json")
cast rpc anvil_setCode "$VRF_ADDR" "$BYTECODE" --rpc-url "$RPC" >/dev/null

cast rpc anvil_impersonateAccount "$DEPOSITOR" --rpc-url "$RPC" >/dev/null
cast rpc anvil_setBalance "$DEPOSITOR" "0x56BC75E2D63100000" --rpc-url "$RPC" >/dev/null

# Enable automine just for setup so individual txs auto-confirm.
cast rpc evm_setAutomine true --rpc-url "$RPC" >/dev/null

PK=$("$ROOT/bin/vrf-prove" -sk "$SK" \
    -seed "0000000000000000000000000000000000000000000000000000000000000000" \
    2>/dev/null | grep "^pk=" | cut -d= -f2)
cast send "$VRF_ADDR" "setSequencerPublicKey(bytes)" "$PK" \
    --from "$DEPOSITOR" --rpc-url "$RPC" --unlocked >/dev/null 2>&1
ok "predeploy + sequencer public key installed"

# ── 5. deploy game contracts ──
deploy() {
    local path="$1" name="$2"
    forge create "$path:$name" \
        --private-key "$DEPLOYER_KEY" --rpc-url "$RPC" --broadcast \
        --root "$CONTRACTS" --json 2>/dev/null | jq -r '.deployedTo'
}

log "deploying games"
FLIP_ADDR=$(deploy "$CONTRACTS/src/examples/CoinFlip.sol" CoinFlip)
DICE_ADDR=$(deploy "$CONTRACTS/src/examples/DiceRoll.sol" DiceRoll)
PLINKO_ADDR=$(deploy "$CONTRACTS/src/examples/Plinko.sol" Plinko)
LOTTERY_ADDR=$(deploy "$CONTRACTS/src/examples/Lottery.sol" Lottery)
JANKEN_ADDR=$(deploy "$CONTRACTS/src/examples/Jankenman.sol" Jankenman)
ok "CoinFlip   $FLIP_ADDR"
ok "DiceRoll   $DICE_ADDR"
ok "Plinko     $PLINKO_ADDR"
ok "Lottery    $LOTTERY_ADDR"
ok "Jankenman  $JANKEN_ADDR"

# Seed the Jankenman LP pool with 50 ETH so bets can actually be paid out
# from the devnet's prefunded deployer account. This hits receive() which
# credits lpAssets without minting shares (it's a donation, not a deposit).
log "seeding Jankenman pool (50 ETH donation to LPs)"
cast send "$JANKEN_ADDR" --value 50ether \
    --private-key "$DEPLOYER_KEY" --rpc-url "$RPC" >/dev/null 2>&1
ok "pool seeded"

# ── 6. write arcade config ──
log "writing arcade/shared/config.js"
cat > "$ARCADE/shared/config.js" <<EOF
// Auto-generated by scripts/arcade.sh — overwritten on every run.
export const CONFIG = {
  chainId:     31337,
  rpc:         '$RPC',
  vrfAddress:  '$VRF_ADDR',
  flip:        '$FLIP_ADDR',
  dice:        '$DICE_ADDR',
  plinko:      '$PLINKO_ADDR',
  lottery:     '$LOTTERY_ADDR',
  jankenman:   '$JANKEN_ADDR',
};
EOF
ok "config written"

# ── 7. switch to manual mining + start sequencer ──
log "starting VRF auto-commit sequencer (every ${INTERVAL}s)"
cast rpc evm_setAutomine false --rpc-url "$RPC" >/dev/null
"$ROOT/scripts/vrf-sequencer.sh" &
PIDS+=($!)
sleep 1.5
ok "sequencer running (pid ${PIDS[$((${#PIDS[@]}-1))]})"

# ── 8. serve arcade/ ──
log "serving arcade/ at http://localhost:$HTTP_PORT "
python3 -m http.server "$HTTP_PORT" --directory "$ARCADE" >/dev/null 2>&1 &
PIDS+=($!)
sleep 0.3

# ── 9. print setup info ──
cat <<EOF

========================================================
   Ready! Open → http://localhost:$HTTP_PORT
========================================================

MetaMask setup (one-time):
  Network name:   Enshrined VRF Devnet
  RPC URL:        $RPC
  Chain ID:       31337  (hex 0x7a69)
  Currency:       ETH

Test accounts (Anvil default — each prefunded with 10000 ETH):
  #0 player      0xf39Fd6e51aad88F6F4ce6aB8827279cfFFb92266
     private key $DEPLOYER_KEY

Contract addresses:
  VRF predeploy  $VRF_ADDR
  CoinFlip       $FLIP_ADDR
  DiceRoll       $DICE_ADDR
  Plinko         $PLINKO_ADDR
  Lottery        $LOTTERY_ADDR
  Jankenman      $JANKEN_ADDR (pool seeded with 50 ETH)

Ctrl-C to stop everything (Anvil + sequencer + web server).

EOF

# Park until Ctrl-C. A sleep-loop is more reliable than `wait <pid>` on
# macOS bash 3.2 for being interrupted by SIGINT → firing the trap.
while :; do
    sleep 1 &
    wait "$!" 2>/dev/null
done
