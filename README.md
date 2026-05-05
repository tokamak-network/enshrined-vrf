# Enshrined VRF

**Protocol-native verifiable randomness for the OP Stack.**

Enshrined VRF embeds an [ECVRF](https://datatracker.ietf.org/doc/html/rfc9381) precompile directly into the OP Stack L2, allowing smart contracts to receive **verifiable, unbiasable randomness in a single transaction** — no oracle, no callback, no extra fee.

```solidity
contract CoinFlip {
    IEnshrainedVRF constant VRF = IEnshrainedVRF(0x42000000000000000000000000000000000000f0);

    function flip() external returns (bool) {
        return (VRF.getRandomness() % 2 == 0);
    }
}
```

## Why

| | Enshrined VRF | External Oracle VRF |
|---|---|---|
| Latency | Same transaction | 2+ transactions (request → callback) |
| Cost | ~24K gas | ~200K+ gas + LINK/subscription |
| Trust | Protocol-level, fault-provable | Oracle network trust assumption |
| Bias resistance | TEE-protected secret key | Oracle-dependent |

## How It Works

```
op-node ────────────────────────────▶ op-geth (sequencer)
  │                                       │
  ├─ seed = sha256(uint256(blockNumber) || uint256(nonce))
  ├─ (beta, pi) = TEE.Prove(seed)  ← sk never leaves enclave
  └─ PayloadAttributes { pk, seed, beta, pi, nonce }
                                          │
                                          ├─ deposit tx → EnshrainedVRF.setSequencerPublicKey(pk)
                                          └─ deposit tx → EnshrainedVRF.commitRandomness(nonce, seed, beta, pi)
                                                              │
                                                              ▼
                                                    User calls getRandomness()
                                                    → returns keccak256(beta, callCounter)
```

1. **op-node** sends seed to the **TEE enclave**, which computes `ECVRF.Prove(sk, seed)` — the secret key never leaves the enclave
2. **op-geth** commits the public key and VRF result via system deposit transactions to `EnshrainedVRF`
3. **Contracts** call `getRandomness()` to consume committed randomness synchronously
4. **Anyone** can verify proofs on-chain using the ECVRF verify precompile at `0x0101`
5. **Fault-proof tooling** can re-execute contracts that call the verify precompile through op-program's ECVRF precompile oracle path

## Operating Modes

The VRF prover runs in two modes, selected via `--sequencer.vrf-mode`:

| | Local (Dev) | TEE (Production) |
|---|---|---|
| **Secret key** | In op-node process memory | Inside TEE enclave only |
| **Operator access to sk** | Can read sk | Cannot access sk |
| **Unpredictability** | Broken — operator knows sk | Guaranteed by hardware isolation |

```bash
# Local mode (development only — sk is exposed to operator)
op-node \
  --sequencer.vrf-mode=local \
  --sequencer.vrf-key=<hex-encoded-sk>

# TEE mode (production — sk never leaves enclave)
# Seal key must come from a platform-bound source (SGX MRSIGNER, TDX REPORTDATA, ...);
# for dev/test pass --dev-seal to derive from hostname (NOT production-safe).
VRF_ENCLAVE_SEAL_KEY=<hex-32B> \
  vrf-enclave --listen unix:///var/run/vrf-enclave.sock --seal-dir /secure/sealed
op-node \
  --sequencer.vrf-mode=tee \
  --sequencer.vrf-tee-endpoint=unix:///var/run/vrf-enclave.sock
```

## Components

| Component | Location | Description |
|-----------|----------|-------------|
| **ECVRF Library** | `crypto/ecvrf/` (mirrored in `op-geth/`) | ECVRF-SECP256K1-SHA256-TAI (RFC 9381) |
| **Verify Precompile** | `op-geth/core/vm/contracts_ecvrf.go` | EVM precompile at `0x0101`, 3,000 gas |
| **EnshrainedVRF** | `optimism/packages/contracts-bedrock/src/L2/` | L2 predeploy at `0x42...f0` |
| **VRFVerifier** | `contracts/src/L1/` | L1 dispute resolution |
| **TEE Enclave** | `vrf-enclave/` | gRPC server, key sealing, attestation |
| **Derivation** | `optimism/op-node/` | Fork config, payload attributes |
| **Block Builder** | `op-geth/miner/` | VRF public-key and randomness deposit injection |

## Quick Start

```bash
# Clone
git clone --recursive https://github.com/tokamak-network/enshrined-vrf.git

# Run all tests
go test ./crypto/ecvrf/ ./core/vm/ -v
cd contracts && forge test -v

# TEE integration tests
cd optimism/op-node/rollup/derive && go test -run TestTEEVRFProver -v

# Start enclave server (dev mode — --dev-seal derives seal key from hostname)
cd vrf-enclave && go run ./cmd/vrf-enclave/ --listen localhost:50051 --seal-dir ./sealed --dev-seal
```

See [docs/testing-guide.md](docs/testing-guide.md) for the full testing guide and [docs/op-stack-customizations.md](docs/op-stack-customizations.md) for the OP Stack integration details.

## Sepolia-Backed Local Devnet

Use the Sepolia devnet scripts when you want the L2 execution client and sequencer to run locally while reading L1 state from Sepolia. The prepare and start scripts reject non-Sepolia RPC URLs and write all local chain data under `.devnet/sepolia`.

```bash
cp devnet/sepolia/.env.example devnet/sepolia/.env
$EDITOR devnet/sepolia/.env

./scripts/devnet-sepolia-prepare.sh
./scripts/devnet-sepolia-start.sh
./scripts/devnet-sepolia-verify-random.sh
```

Or run the ordered flow with one command:

```bash
./scripts/devnet-sepolia-up.sh
```

To check local prerequisites without deploying anything to Sepolia:

```bash
./scripts/devnet-sepolia-preflight.sh
```

Default endpoints:

| Service | URL |
|---------|-----|
| L2 RPC | `http://127.0.0.1:9545` |
| L2 WebSocket | `ws://127.0.0.1:9546` |
| op-node RPC | `http://127.0.0.1:7545` |

The verification step checks that the `EnshrainedVRF` predeploy exists, `commitNonce()` advances, the L2 sequencer public key is synced from Sepolia `SystemConfig`, `getRandomness()` returns a value, and a `CoinFlip` consumer can call randomness in a local L2 transaction.

See [docs/sepolia-devnet.md](docs/sepolia-devnet.md) for the full runbook.

## Arcade Demo

A one-shot local demo of several VRF-powered games — CoinFlip, DiceRoll,
Plinko, Lottery, Pongy.bet (짱깸뽀) — all settling randomness through
the EnshrainedVRF predeploy:

```bash
./scripts/arcade.sh
# → Anvil + ArcadeVRF predeploy + 5 game contracts + auto-commit
#   sequencer daemon (1 block/s) + arcade UI at http://localhost:5173
```

Under the hood, `scripts/arcade.sh` builds the `vrf-prove` CLI, starts
Anvil with automine OFF, installs [`ArcadeVRF`](contracts/src/examples/ArcadeVRF.sol)
(a demo-only IEnshrainedVRF drop-in) at the predeploy address, and
then delegates per-block randomness commits to [`scripts/vrf-sequencer.sh`](scripts/vrf-sequencer.sh).

## Specifications

| Parameter | Value |
|-----------|-------|
| Algorithm | ECVRF-SECP256K1-SHA256-TAI (RFC 9381) |
| Proof size | 81 bytes |
| Output size | 32 bytes |
| Precompile address | `0x0101` |
| Predeploy address | `0x42000000000000000000000000000000000000f0` |
| Verify gas | 3,000 |
| Fork name | `EnshrainedVRF` |

## Security

- **TEE-protected secret key**: sk lives exclusively inside the TEE enclave — the sequencer operator cannot access it
- **Deterministic seed**: `seed = sha256(uint256(blockNumber) || uint256(nonce))` — security relies on TEE key isolation, not seed entropy
- **Fault-proof compatible**: op-program supports the ECVRF verify precompile path, and committed `(pk, seed, beta, pi)` tuples can be challenged or monitored independently

## License

MIT
