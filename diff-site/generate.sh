#!/bin/bash
# Generate forkdiff HTML pages for Enshrined VRF changes.
# Produces op-geth.html and optimism.html plus an index page.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FORKDIFF="$SCRIPT_DIR/forkdiff"
OUT_DIR="$SCRIPT_DIR/out"

if [ ! -f "$FORKDIFF" ]; then
  echo "ERROR: forkdiff binary not found at $FORKDIFF"
  echo "Build it: cd /tmp && git clone https://github.com/protolambda/forkdiff && cd forkdiff && go build -o $FORKDIFF ."
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "==> Generating op-geth diff page..."
"$FORKDIFF" \
  -repo "$ROOT_DIR/op-geth" \
  -fork "$SCRIPT_DIR/op-geth-fork.yaml" \
  -out "$OUT_DIR/op-geth.html"
echo "    Done: $OUT_DIR/op-geth.html"

echo "==> Generating optimism diff page..."
"$FORKDIFF" \
  -repo "$ROOT_DIR/optimism" \
  -fork "$SCRIPT_DIR/optimism-fork.yaml" \
  -out "$OUT_DIR/optimism.html"
echo "    Done: $OUT_DIR/optimism.html"

echo "==> Generating index page..."
cat > "$OUT_DIR/index.html" << 'INDEXEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Enshrined VRF — OP Stack Fork Diff</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
      background: #0d1117;
      color: #c9d1d9;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 40px 20px;
    }
    h1 { font-size: 32px; color: #f0f6fc; margin-bottom: 8px; }
    .subtitle { color: #8b949e; margin-bottom: 40px; font-size: 16px; }
    .cards { display: flex; gap: 24px; flex-wrap: wrap; justify-content: center; }
    .card {
      background: #161b22;
      border: 1px solid #30363d;
      border-radius: 12px;
      padding: 32px;
      width: 340px;
      text-decoration: none;
      color: #c9d1d9;
      transition: border-color 0.2s, transform 0.2s;
    }
    .card:hover { border-color: #58a6ff; transform: translateY(-2px); }
    .card h2 { font-size: 20px; color: #f0f6fc; margin-bottom: 12px; }
    .card p { font-size: 14px; color: #8b949e; line-height: 1.6; }
    .card .tag {
      display: inline-block;
      background: #21262d;
      color: #58a6ff;
      padding: 4px 10px;
      border-radius: 12px;
      font-size: 12px;
      margin-top: 16px;
    }
    .footer { margin-top: 60px; color: #484f58; font-size: 12px; text-align: center; }
    .footer a { color: #58a6ff; text-decoration: none; }
  </style>
</head>
<body>
  <h1>Enshrined VRF</h1>
  <p class="subtitle">OP Stack fork diff — ECVRF precompile integration</p>
  <div class="cards">
    <a class="card" href="op-geth.html">
      <h2>op-geth</h2>
      <p>
        ECVRF Go library, verify precompile at 0x0101,
        fork activation config, sequencer VRF block building,
        Engine API PayloadAttributes extension.
      </p>
      <span class="tag">Execution Layer</span>
    </a>
    <a class="card" href="optimism.html">
      <h2>optimism</h2>
      <p>
        Fork registration, derivation pipeline extension,
        VRF deposit tx creation, SystemConfig event parsing,
        predeploy address registration, L1 contract changes.
      </p>
      <span class="tag">Consensus Layer + Contracts</span>
    </a>
  </div>
  <div class="footer">
    <p><a href="https://github.com/tokamak-network/enshrined-vrf">tokamak-network/enshrined-vrf</a>
    &middot; created with <a href="https://github.com/protolambda/forkdiff">forkdiff</a></p>
  </div>
</body>
</html>
INDEXEOF
echo "    Done: $OUT_DIR/index.html"

echo ""
echo "==> All done! Open $OUT_DIR/index.html"
