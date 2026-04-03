# Phase 3 Completion Report — Derivation Pipeline & OP Stack Integration

**Date**: 2026-04-02  
**Status**: Complete (Core Integration)

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
| **op-geth** | `beacon/engine/types.go` | `VRFPublicKey` field in `PayloadAttributes` |
| **op-geth** | `miner/vrf_config.go` | `VRFConfig` struct for sequencer VRF key management (new file) |
| **optimism** | `op-core/forks/forks.go` | `EnshrainedVRF` fork name, added to `All` list |
| **optimism** | `op-node/rollup/types.go` | `EnshrainedVRFTime` field, `IsEnshrainedVRF()`, `ActivationTime`, `SetActivationTime` |
| **optimism** | `op-node/rollup/superchain.go` | Comment placeholder for hardfork mapping |
| **optimism** | `op-node/rollup/derive/attributes.go` | `VRFPublicKey` in PayloadAttributes construction |
| **optimism** | `op-node/rollup/derive/vrf_deposit.go` | VRF system deposit tx creation (new file) |
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
  2. Include in PayloadAttributes.VRFPublicKey
  3. If PK changed → VRFSetPublicKeyDeposit → PredeployedVRF.setSequencerPublicKey()
  4. For each block → ecvrf.Prove(sk, seed) → VRFCommitRandomnessDeposit → PredeployedVRF.commitRandomness()
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

VRF uses its own system deposit transaction to call `PredeployedVRF` instead of extending `L1BlockInfo` marshaling. This keeps concerns separate and avoids changing the L1Block predeploy.

### VRF Private Key Management

The sequencer's VRF private key is held in `miner.VRFConfig`, never exposed to EVM. During block building, the sequencer calls `ecvrf.Prove()` in Go code and injects the result as a deposit tx.

### Fork Ordering

```
... → Isthmus → Jovian → Karst → Interop → EnshrainedVRF
```

EnshrainedVRF is placed after Interop in the fork ordering, as the latest mainline fork.

---

## 4. Build Status

| Component | Build | Notes |
|-----------|-------|-------|
| op-geth `core/vm/` | ✅ Pass | Precompile compiles and links correctly |
| op-geth `miner/` | ✅ Pass | VRFConfig compiles |
| op-geth `beacon/engine/` | ✅ Pass | PayloadAttributes extension compiles |
| op-geth `crypto/ecvrf/` | ✅ Pass | ECVRF library compiles within op-geth module |
| optimism (not fully built) | ⚠️ Partial | Individual file changes validated; full monorepo build requires CI |

---

## 5. Files Created/Modified

### New Files (4)
- `op-geth/core/vm/contracts_ecvrf.go` — Verify precompile
- `op-geth/miner/vrf_config.go` — VRF sequencer config
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

## 6. Remaining Work for Full Integration

Phase 3 establishes the core framework. The following items require deeper integration and E2E testing:

1. **op-geth worker.go**: Full integration of VRF prove + deposit tx injection during `commitWork()`
2. **Engine API handler**: Parsing `VRFPublicKey` from `ForkchoiceUpdatedV3` and passing to worker
3. **SystemConfig event parsing**: Reading `VRFPublicKeyUpdated` events from L1 SystemConfig
4. **genesis allocs**: PredeployedVRF bytecode in L2 genesis
5. **E2E devnet test**: Full flow from L1 SystemConfig → op-node → op-geth → user contract

---

## 7. Next Steps (Phase 4)

1. L1 SystemConfig contract modifications (Solidity)
2. Fault proof op-program integration
3. E2E testing with devnet
