#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${DEVNET_WORKDIR:-$ROOT/.devnet/sepolia}"

stop_pid() {
  local name="$1"
  local pidfile="$2"
  if [ ! -f "$pidfile" ]; then
    echo "[stop] $name not running (no pid file)"
    return
  fi
  local pid
  pid="$(cat "$pidfile")"
  if kill -0 "$pid" >/dev/null 2>&1; then
    echo "[stop] stopping $name pid $pid"
    kill "$pid"
    for _ in $(seq 1 20); do
      if ! kill -0 "$pid" >/dev/null 2>&1; then
        rm -f "$pidfile"
        return
      fi
      sleep 1
    done
    echo "[stop] $name did not exit after 20s; sending SIGKILL"
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi
  rm -f "$pidfile"
}

stop_pid op-node "$WORKDIR/op-node.pid"
stop_pid op-geth "$WORKDIR/geth.pid"

echo "[stop] done"
