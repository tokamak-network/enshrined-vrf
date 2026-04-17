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
                                          │
                                          ├─ seed = sha256(blockNumber)
                                          ├─ (beta, pi) = TEE.Prove(seed)  ← sk never leaves enclave
                                          └─ deposit tx → PredeployedVRF.commitRandomness()
                                                              │
                                                              ▼
                                                    User calls getRandomness()
                                                    → returns beta (verifiable output)
```

1. **Sequencer** sends seed to the **TEE enclave**, which computes `ECVRF.Prove(sk, seed)` — the secret key never leaves the enclave
2. **Result** is committed via a system deposit transaction to `PredeployedVRF`
3. **Contracts** call `getRandomness()` to consume committed randomness synchronously
4. **Anyone** can verify proofs on-chain using the ECVRF verify precompile at `0x0101`
5. **Fault proofs** detect invalid VRF outputs — the sequencer cannot cheat

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

See [docs/testing-guide.md](docs/testing-guide.md) for the full testing guide including devnet setup and troubleshooting.

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
- **Deterministic seed**: `seed = sha256(blockNumber)` — security relies on TEE key isolation, not seed entropy
- **Fault provable**: invalid VRF outputs cause state root divergence, detectable by Cannon/Asterisc

## License

MIT
