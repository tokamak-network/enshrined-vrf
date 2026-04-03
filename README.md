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
| Bias resistance | L1 RANDAO in seed | Oracle-dependent |

## How It Works

```
L1 Block (RANDAO)
    │
    ▼
op-node ──── derives prevrandao ────▶ op-geth (sequencer)
                                          │
                                          ├─ seed = sha256(prevrandao, blockNum, nonce)
                                          ├─ (beta, pi) = ecvrf.Prove(sk, seed)
                                          └─ deposit tx → PredeployedVRF.commitRandomness()
                                                              │
                                                              ▼
                                                    User calls getRandomness()
                                                    → returns beta (verifiable output)
```

1. **Sequencer** computes `ECVRF.Prove(sk, seed)` during block building — the secret key never touches the EVM
2. **Result** is committed via a system deposit transaction to `PredeployedVRF`
3. **Contracts** call `getRandomness()` to consume committed randomness synchronously
4. **Anyone** can verify proofs on-chain using the ECVRF verify precompile at `0x0101`
5. **Fault proofs** detect invalid VRF outputs — the sequencer cannot cheat

## Architecture

```mermaid
graph TB
    subgraph op-geth["op-geth (Execution Layer)"]
        ecvrf["crypto/ecvrf<br/><i>Go library</i><br/>Prove() / Verify()"]
        predeploy["PredeployedVRF<br/><i>0x42...f0</i><br/>commit() / getRandomness()"]
        precompile["ECVRF Verify<br/><i>Precompile 0x0101</i><br/>Verify()"]
        ecvrf -->|"deposit tx"| predeploy
        precompile -.->|"on-chain verify"| predeploy
    end

    subgraph op-node["op-node (Consensus Layer)"]
        derivation["Derivation Pipeline<br/>EnshrainedVRFTime fork activation<br/>VRF public key from L1 SystemConfig<br/>VRF deposit tx creation"]
    end

    subgraph l1["L1 Contracts (Ethereum)"]
        sysconfig["SystemConfig<br/>setVRFPublicKey()"]
        verifier["VRFVerifier<br/>dispute resolution"]
    end

    l1 -->|"prevrandao + VRF key"| op-node
    op-node -->|"PayloadAttributes"| op-geth
```

## Components

| Component | Location | Description |
|-----------|----------|-------------|
| **ECVRF Library** | `crypto/ecvrf/` | ECVRF-SECP256K1-SHA256-TAI (RFC 9381), constant-time ModNScalar |
| **Verify Precompile** | `core/vm/` | EVM precompile at `0x0101`, 3,000 gas |
| **PredeployedVRF** | `contracts/src/` | L2 predeploy at `0x42...f0`, dual-nonce design |
| **VRFVerifier** | `contracts/src/L1/` | L1 dispute resolution (proof-to-hash, seed verification) |
| **Block Builder** | `op-geth/miner/` | Sequencer VRF prove + deposit tx injection |
| **Derivation** | `optimism/op-node/` | Fork config, payload attributes, event parsing |
| **SystemConfig** | `optimism/.../L1/` | VRF public key management on L1 |

## Specifications

| Parameter | Value |
|-----------|-------|
| Algorithm | ECVRF-SECP256K1-SHA256-TAI (RFC 9381) |
| Suite string | `0xFE` (custom) |
| Proof size | 81 bytes (33 point + 16 challenge + 32 scalar) |
| Output size | 32 bytes |
| Precompile address | `0x0101` |
| Predeploy address | `0x42000000000000000000000000000000000000f0` |
| Verify gas | 3,000 |
| Prove latency | ~0.35ms |
| Verify latency | ~0.42ms |
| Fork name | `EnshrainedVRF` |

## Security

- **Secret key isolation**: The VRF private key exists only in Go memory during block building — never in EVM calldata, storage, or traces
- **Bias resistance**: Seed includes L1 RANDAO (`prevrandao`), which the sequencer cannot manipulate alone
- **Tamper detection**: 100% bit-flip rejection rate across all 648 proof bits
- **Constant-time arithmetic**: All secret scalar operations use `ModNScalar` to prevent timing side channels
- **Fault provable**: Invalid VRF outputs cause state root divergence, detectable by Cannon/Asterisc

## Testing

```
82 tests | 164K+ fuzz iterations | 0 crashes | 100% bit-flip rejection
```

| Suite | Tests | Coverage |
|-------|-------|----------|
| ECVRF Go library | 22 + 2 fuzz | Prove/Verify round-trip, determinism, tampering, distribution |
| Verify precompile | 9 | All input variants, gas calibration |
| PredeployedVRF | 31 | Access control, nonce, events, batch, integration |
| VRFVerifier | 20 + fuzz | Proof-to-hash, seed, nonce sequence, known vectors |

```bash
# Run Go tests
go test ./crypto/ecvrf/ -v
go test ./core/vm/ -v

# Run Solidity tests
cd contracts && forge test -v

# Run fuzz (30 seconds)
go test ./crypto/ecvrf/ -fuzz=FuzzProveVerify -fuzztime=30s
```

## Fork Diff

View the exact changes against upstream OP Stack:

```bash
cd diff-site && bash generate.sh && open out/index.html
```

Generated with [protolambda/forkdiff](https://github.com/protolambda/forkdiff), showing structured diffs for both [op-geth](https://github.com/ethereum-optimism/op-geth) and [optimism](https://github.com/ethereum-optimism/optimism).

## Repository Structure

```
enshrined-vrf/
├── crypto/ecvrf/              # ECVRF Go library (standalone)
├── core/vm/                   # Verify precompile (standalone)
├── contracts/                 # Solidity contracts + Foundry tests
│   ├── src/
│   │   ├── PredeployedVRF.sol          # L2 predeploy
│   │   ├── interfaces/IEnshrainedVRF.sol
│   │   └── L1/VRFVerifier.sol          # L1 dispute resolution
│   └── test/
├── op-geth/                   # Forked op-geth (submodule)
├── optimism/                  # Forked optimism (submodule)
├── diff-site/                 # forkdiff viewer
├── e2e/                       # E2E test scaffolding
└── docs/
    ├── PRD.md
    ├── architecture.md
    ├── security-audit-checklist.md
    └── phase-{1,2,3,4}-report.md
```

## Building

```bash
# Clone with submodules
git clone --recursive https://github.com/tokamak-network/enshrined-vrf.git

# Build ECVRF library
go build ./crypto/ecvrf/

# Build Solidity contracts
cd contracts && forge build

# Run all tests
go test ./crypto/ecvrf/ ./core/vm/
cd contracts && forge test
```

## License

MIT
