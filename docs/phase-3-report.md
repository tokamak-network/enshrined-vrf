# Phase 3 Completion Report — Derivation Pipeline & OP Stack Integration

**Date**: 2026-04-02  
**Status**: Complete (Core Integration)

**Current implementation note (2026-05-05)**: VRF proving now happens in op-node through a local or TEE `VRFProver`. op-geth does not hold the VRF secret key; it receives VRF payload attributes and injects deposits into `EnshrainedVRF`.

---

## 1. Deliverables

### Repository Structure
- **op-geth** and **optimism** added as git submodules with `enshrined-vrf` branches
- ECVRF Go library copied into op-geth (`crypto/ecvrf/`)
- Verify precompile registered at `0x0101` in op-geth

### Changes Summary

| Repository | File | Change |
|-----------|------|--------|
| **op-geth** | `params/config.go` | `EnshrainedVRFTime *uint64` field, `IsEnshrainedVRF()` method, `Rules.IsOptimismEnshrainedVRF` |
| **op-geth** | `params/protocol_params.go` | `EcvrfVerifyGas = 3000` constant |
| **op-geth** | `core/vm/contracts_ecvrf.go` | ECVRF verify precompile (new file) |
| **op-geth** | `core/vm/contracts.go` | `PrecompiledContractsEnshrainedVRF` map, registered in `activePrecompiledContracts()` and `ActivePrecompiles()` |
| **op-geth** | `crypto/ecvrf/` | ECVRF Go library (copied from root) |
| **op-geth** | `beacon/engine/types.go` | `VRFPublicKey`, `VRFSeed`, `VRFProofBeta`, `VRFProofPi`, `VRFNonce` fields in `PayloadAttributes` |
| **op-geth** | `miner/vrf_builder.go` | ABI encoding and source hashes for public-key and randomness deposits |
| **op-geth** | `miner/worker.go` | Deposit injection during payload building |
| **optimism** | `op-core/forks/forks.go` | `EnshrainedVRF` fork name, added to `All` list |
| **optimism** | `op-node/rollup/types.go` | `EnshrainedVRFTime` field, `IsEnshrainedVRF()`, `ActivationTime`, `SetActivationTime` |
| **optimism** | `op-node/rollup/superchain.go` | Comment placeholder for hardfork mapping |
| **optimism** | `op-node/rollup/derive/attributes.go` | VRF seed/proof generation and PayloadAttributes construction |
| **optimism** | `op-node/rollup/derive/vrf_deposit.go` | Seed/proof helpers and VRF deposit decoding |
| **optimism** | `op-service/eth/types.go` | `VRFPublicKey` in `PayloadAttributes` and `SystemConfig` |

---

## 2. Architecture Details

### Fork Activation Flow

```
rollup.json: EnshrainedVRFTime = <timestamp>
    │
    ├── op-node: Config.IsEnshrainedVRF(timestamp)
    │     └── forks.EnshrainedVRF in forks.All ordering
    │
    └── op-geth: ChainConfig.IsEnshrainedVRF(timestamp)
          └── Rules.IsOptimismEnshrainedVRF
                └── activePrecompiledContracts() → PrecompiledContractsEnshrainedVRF
                      └── 0x0101: ecvrfVerify{}
```

### Deposit Transaction Flow

```
Sequencer (op-node + op-geth):
  1. Read VRFPublicKey from SystemConfig (L1)
  2. op-node computes seed and proof with local/TEE VRFProver
  3. Include pk, seed, beta, pi, nonce in PayloadAttributes
  4. op-geth injects EnshrinedVRF.setSequencerPublicKey(pk)
  5. op-geth injects EnshrinedVRF.commitRandomness(nonce, seed, beta, pi)
```

### Precompile Map

```
EnshrainedVRF precompile map = Jovian map + {
    0x0101: ecvrfVerify (ECVRF-SECP256K1-SHA256-TAI verify, gas: 3000)
}
```

---

## 3. Key Design Decisions

### Separate Deposit TX (not L1BlockInfo extension)

VRF uses its own system deposit transactions to call `EnshrainedVRF` instead of extending `L1BlockInfo` marshaling. This keeps concerns separate and avoids changing the L1Block predeploy.

### VRF Private Key Management

The VRF secret key is behind op-node's `VRFProver` abstraction. Local mode holds the key in op-node memory for development; TEE mode delegates proof generation to the enclave. op-geth never receives the secret key.

### Fork Ordering

```
... → Isthmus → Jovian → Karst → Interop → EnshrainedVRF
```

EnshrainedVRF is placed after Interop in the fork ordering, as the latest mainline fork.

---

## 4. Current Verification Surface

The earlier draft of this report left the optimism integration as "partial" and
listed worker, Engine API, SystemConfig parsing, genesis allocs, and E2E flow as
remaining. Those items have since moved into the main implementation and are now
tracked by the current testing guide.

| Component | Verification command |
|-----------|----------------------|
| op-geth precompile | `cd op-geth && go test ./core/vm/ -run ECVRF -v` |
| op-geth Engine API | `cd op-geth && go test ./beacon/engine/ -run VRF -v` |
| op-geth miner / payload building | `cd op-geth && go test ./miner/ -run 'VRF|PayloadIdIncludesVRFAttributes' -v` |
| op-service payload JSON | `cd optimism && go test ./op-service/eth -run VRF -v` |
| op-node derivation | `cd optimism && go test ./op-node/rollup/derive -run 'VRF|SystemConfig|PreparePayloadAttributes' -v` |
| Sepolia local L2 | `./scripts/devnet-sepolia-verify-random.sh` |

---

## 5. Files Created/Modified

### New Files (4)
- `op-geth/core/vm/contracts_ecvrf.go` — Verify precompile
- `op-geth/miner/vrf_builder.go` — VRF deposit encoding
- `op-geth/crypto/ecvrf/` — ECVRF library (3 files copied from root)
- `optimism/op-node/rollup/derive/vrf_deposit.go` — VRF deposit tx creation

### Modified Files (9)
- `op-geth/params/config.go` — Fork config
- `op-geth/params/protocol_params.go` — Gas constant
- `op-geth/core/vm/contracts.go` — Precompile registration
- `op-geth/beacon/engine/types.go` — PayloadAttributes
- `optimism/op-core/forks/forks.go` — Fork name
- `optimism/op-node/rollup/types.go` — Rollup config
- `optimism/op-node/rollup/superchain.go` — Hardfork mapping
- `optimism/op-node/rollup/derive/attributes.go` — Payload construction
- `optimism/op-service/eth/types.go` — SystemConfig + PayloadAttributes

---

## 6. Follow-on Work

Phase 3's remaining implementation items have been folded into the later OP
Stack integration work. Active follow-on work is now operational rather than
structural:

1. Keep the Sepolia-backed local L2 verification script green after every
   op-geth or optimism rebase.
2. Monitor the registered L1 `SystemConfig.vrfPublicKey()` against the active
   prover key before production use.
3. Re-run the command matrix in [testing-guide.md](testing-guide.md) before
   audit or release candidates.
