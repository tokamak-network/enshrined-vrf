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
│  │   L1 Block   │     │   SystemConfig   │                         │
│  │              │     │                  │                         │
│  │  mixHash     │     │  vrfPublicKey()  │                         │
│  │  (RANDAO)    │     │  setVRFPublicKey()│                        │
│  └──────┬───────┘     └────────┬─────────┘                         │
│         │                      │                                    │
└─────────┼──────────────────────┼────────────────────────────────────┘
          │                      │
          ▼                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         op-node (Derivation)                        │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │                  Derivation Pipeline                      │      │
│  │                                                          │      │
│  │  L1Traversal ──▷ Read mixHash (prevrandao)               │      │
│  │  SystemConfig ──▷ Read vrfPublicKey                      │      │
│  │                                                          │      │
│  │  PayloadAttributes {                                     │      │
│  │    prevRandao:    l1Block.mixHash,                       │      │
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
│  │  For each VRF request in the block:                      │      │
│  │    1. seed = keccak256(prevrandao, block.number, nonce)  │      │
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
           │     (prevrandao, vrfPublicKey)
           │
           │  2. For N expected VRF calls:
           │     seed_i = keccak256(prevrandao, blockNum, i)
           │     (beta_i, pi_i) = ecvrf.Prove(sk, seed_i)
           │
           │  3. Create deposit tx:
           │     PredeployedVRF.commitRandomness(i, beta_i, pi_i)
           │
           ├──────────────────────────────▷│
           │                               │  4. Execute deposit tx
           │                               │     Store (nonce, beta, pi)
           │                               │     Emit RandomnessCommitted
           │                               │
           │                               │  5. Execute user txs
           │                               │     ├─────────────────────▷│
           │                               │     │                      │  6. VRF.getRandomness()
           │                               │     │                      │     Read committed beta
           │                               │     │◁─────────────────────│     Return to caller
           │                               │     │    uint256(beta)     │
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
Slot 0: uint256 _nonce                    (current nonce, monotonically increasing)
Slot 1: bytes   _sequencerPublicKey       (33 bytes, compressed SEC1)

Dynamic mapping:
  keccak256(nonce . slot_2): VRFResult {
    bytes32 beta     (32 bytes)
    bytes   pi       (81 bytes)
  }
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
