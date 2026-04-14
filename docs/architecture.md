# Enshrined VRF — Architecture Document

**Version**: 2.0  
**Date**: 2026-04-02

---

## 1. System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                            L1 (Ethereum)                            │
│                                                                     │
│  ┌──────────────┐     ┌──────────────────┐                         │
│  │   SystemConfig                │                                 │
│  │                               │                                 │
│  │   vrfPublicKey()              │                                 │
│  │   setVRFPublicKey()           │                                 │
│  └──────────────┬────────────────┘                                 │
│                 │                                                   │
└─────────────────┼───────────────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         op-node (Derivation)                        │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │                  Derivation Pipeline                      │      │
│  │                                                          │      │
│  │  SystemConfig ──▷ Read vrfPublicKey                      │      │
│  │                                                          │      │
│  │  PayloadAttributes {                                     │      │
│  │    vrfPublicKey:  systemConfig.vrfPublicKey,             │      │
│  │    ...                                                   │      │
│  │  }                                                       │      │
│  └──────────────────────────┬───────────────────────────────┘      │
│                             │                                       │
└─────────────────────────────┼───────────────────────────────────────┘
                              │ Engine API
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       op-geth (Execution)                           │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │                  Block Building (Sequencer)               │      │
│  │                                                          │      │
│  │  VRF commitment (once per block):                         │      │
│  │    1. seed = sha256(block.number, nonce)                  │      │
│  │    2. (beta, pi) = ecvrf.Prove(sequencer_sk, seed)       │      │
│  │    3. Create deposit tx:                                 │      │
│  │       PredeployedVRF.commitRandomness(nonce, beta, pi)   │      │
│  │                                                          │      │
│  └──────────────────────────┬───────────────────────────────┘      │
│                             │                                       │
│  ┌──────────────────────────▼───────────────────────────────┐      │
│  │                    EVM Execution                          │      │
│  │                                                          │      │
│  │  ┌─────────────────────┐    ┌──────────────────────┐     │      │
│  │  │  PredeployedVRF     │    │  ECVRF Verify        │     │      │
│  │  │  (0x42...F0)        │    │  Precompile (0x0101) │     │      │
│  │  │                     │    │                      │     │      │
│  │  │  commitRandomness() │    │  Input: pk, seed,    │     │      │
│  │  │  getRandomness()    │◀──▶│         beta, pi     │     │      │
│  │  │  getResult()        │    │  Output: valid/      │     │      │
│  │  │  sequencerPublicKey │    │          invalid     │     │      │
│  │  └─────────┬───────────┘    └──────────────────────┘     │      │
│  │            │                                              │      │
│  │            ▼                                              │      │
│  │  ┌─────────────────────┐                                 │      │
│  │  │  User Contracts     │                                 │      │
│  │  │  (CoinFlip, etc.)   │                                 │      │
│  │  │                     │                                 │      │
│  │  │  VRF.getRandomness()│                                 │      │
│  │  └─────────────────────┘                                 │      │
│  └──────────────────────────────────────────────────────────┘      │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │              crypto/ecvrf (Go Library)                    │      │
│  │                                                          │      │
│  │  Prove(sk, alpha) → (beta, pi)    [Sequencer only]      │      │
│  │  Verify(pk, alpha, pi) → (valid, beta)  [Anyone]        │      │
│  │  ProofToHash(pi) → beta                                 │      │
│  └──────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. VRF Lifecycle (Per Block)

```
  Sequencer (Block Building)              EVM Execution               User Contract
  ========================              =============               =============
           │
           │  1. Receive PayloadAttributes
           │     (vrfPublicKey)
           │
           │  2. Compute VRF (once per block):
           │     seed = sha256(blockNum, nonce)
           │     (beta, pi) = ecvrf.Prove(sk, seed)
           │
           │  3. Create one deposit tx:
           │     PredeployedVRF.commitRandomness(nonce, seed, beta, pi)
           │
           ├──────────────────────────────▷│
           │                               │  4. Execute deposit tx
           │                               │     Store beta, reset callCounter
           │                               │     Emit RandomnessCommitted
           │                               │
           │                               │  5. Execute user txs
           │                               │     ├─────────────────────▷│
           │                               │     │                      │  6. VRF.getRandomness()
           │                               │     │                      │     keccak256(beta, callCounter++)
           │                               │     │◁─────────────────────│     Return unique value
           │                               │     │                      │
```

---

## 3. Fault Proof Flow

```
  Challenger                    L1 Dispute Game                  Cannon/Asterisc
  ==========                    ================                  ===============
       │
       │  1. Detect invalid VRF result
       │     (beta/pi doesn't verify,
       │      or seed mismatch)
       │
       ├──▷│
       │   │  2. Bisect to find
       │   │     divergent instruction
       │   │
       │   │  3. Single-step execution
       │   ├──────────────────────────────▷│
       │   │                               │  4. Re-execute block
       │   │                               │     with op-geth + precompile
       │   │                               │
       │   │                               │  5. Deposit tx replays:
       │   │                               │     commitRandomness(n, beta, pi)
       │   │                               │     → same state transition
       │   │                               │
       │   │                               │  6. If sequencer committed
       │   │◁──────────────────────────────│     wrong (beta, pi):
       │   │   State root mismatch         │     state root differs
       │   │
       │◁──│  7. Challenger wins
```

### Verification Methods

```
┌─────────────────────────────────────────────────────┐
│              Verification on L1                      │
│                                                     │
│  Given: (pk, seed, beta, pi) from L2 state          │
│                                                     │
│  Method 1: Cannon re-execution                      │
│    op-program includes ECVRF verify precompile      │
│    → re-executes L2 block → state root comparison   │
│                                                     │
│  Method 2: Direct verification (optional)           │
│    Solidity ECVRF.verify(pk, seed, beta, pi)        │
│    → on-chain verification without re-execution     │
└─────────────────────────────────────────────────────┘
```

---

## 4. Storage Layout — PredeployedVRF

```
Slot 0: bytes   _sequencerPublicKey       (33 bytes, compressed SEC1)
Slot 1: uint256 _commitNonce              (one per block, monotonically increasing)
Slot 2: bytes32 _currentBeta              (beta for the current block)
Slot 3: uint256 _currentBlock             (block number of current commitment)
Slot 4: uint256 _callCounter              (per-call derivation counter, resets each block)

Dynamic mapping:
  keccak256(nonce . slot_5): VrfResult {
    bytes32 seed         (32 bytes)
    bytes32 beta         (32 bytes)
    bytes   pi           (81 bytes)
    uint256 blockNumber  (block number)
  }

Per-call derivation:
  getRandomness() returns keccak256(beta, callCounter++)
  Each call in the same block receives a unique value.
```

---

## 5. Fork Activation

```
Timeline:
  ... → Fjord → Granite → Holocene → Isthmus → Interop → EnshrainedVRF
                                                              │
                                                     EnshrainedVRFTime
                                                     (unix timestamp)

Config propagation:
  rollup.json (EnshrainedVRFTime)
       │
       ├──▷ op-node rollup.Config
       │      └──▷ IsEnshrainedVRF(timestamp)
       │
       └──▷ op-geth ChainConfig
              └──▷ IsEnshrainedVRF(timestamp)
                     └──▷ Rules.IsOptimismEnshrainedVRF
                            └──▷ activePrecompiledContracts()
                                   └──▷ PrecompiledContractsEnshrainedVRF
```

---

## 6. Key Management

```
┌─────────────────────────────────────┐
│          Key Lifecycle               │
│                                     │
│  1. Generate secp256k1 keypair      │
│     sk (private) → HSM/KMS          │
│     pk (public, 33 bytes compressed)│
│                                     │
│  2. Register on L1                  │
│     SystemConfig.setVRFPublicKey(pk)│
│     → emits VRFPublicKeyUpdated    │
│                                     │
│  3. Propagate to L2                 │
│     op-node reads SystemConfig      │
│     → deposit tx to PredeployedVRF  │
│     → setSequencerPublicKey(pk)     │
│                                     │
│  4. Sequencer uses sk               │
│     op-geth reads from config/env   │
│     → ecvrf.Prove(sk, seed)         │
│     → result in deposit tx          │
│                                     │
│  5. Anyone verifies with pk         │
│     PredeployedVRF.sequencerPublicKey()│
│     → ECVRF verify precompile      │
└─────────────────────────────────────┘
```

---

## 7. Precompile Address Space

```
OP Stack Precompile Addresses:
  0x0100  P256VERIFY      (Fjord)
  0x0101  ECVRF_VERIFY    (EnshrainedVRF) ← NEW
```
