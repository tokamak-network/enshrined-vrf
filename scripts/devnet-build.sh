#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT/bin"

mkdir -p "$BIN_DIR" "$ROOT/.devnet/go-build-cache"

export GOCACHE="${GOCACHE:-$ROOT/.devnet/go-build-cache}"

echo "[build] GOCACHE=$GOCACHE"

echo "[build] bin/geth"
(cd "$ROOT/op-geth" && go build -o "$BIN_DIR/geth" ./cmd/geth)

echo "[build] bin/op-node"
(cd "$ROOT/optimism" && go build -o "$BIN_DIR/op-node" ./op-node/cmd)

echo "[build] bin/op-deployer"
(cd "$ROOT/optimism" && go build -o "$BIN_DIR/op-deployer" ./op-deployer/cmd/op-deployer)

echo "[build] bin/vrf-prove"
(cd "$ROOT" && go build -o "$BIN_DIR/vrf-prove" ./vrf-enclave/cmd/vrf-prove)

echo "[build] done"
