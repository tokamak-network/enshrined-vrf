# Enshrined VRF Architecture

**Version**: 2.1
**Date**: 2026-05-05

This document describes the runtime architecture. For the complete OP Stack file-level change map, see [op-stack-customizations.md](op-stack-customizations.md).

## 1. System Architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│                         L1 Ethereum                              │
│                                                                  │
│  SystemConfig                                                    │
│  - setVRFPublicKey(bytes pk)      owner only                     │
│  - vrfPublicKey()                 33-byte compressed SEC1 key    │
│  - ConfigUpdate(VRF_PUBLIC_KEY)   consumed by op-node            │
└──────────────────────────────┬───────────────────────────────────┘
                               │ L1 receipts / SystemConfig updates
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                         op-node                                  │
│                                                                  │
│  Derivation                                                      │
│  - parses SystemConfig VRF public-key updates                    │
│  - carries VRF fields through singular/span batches              │
│                                                                  │
│  Sequencer proving                                               │
│  - seed = SHA256(uint256(blockNumber) || uint256(nonce))         │
│  - (beta, pi) = VRFProver.Prove(seed)                            │
│  - VRFProver is local for dev or TEE-backed for production        │
│                                                                  │
│  Engine API PayloadAttributes                                    │
│  - vrfPublicKey, vrfSeed, vrfProofBeta, vrfProofPi, vrfNonce     │
└──────────────────────────────┬───────────────────────────────────┘
                               │ engine_forkchoiceUpdatedV*
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                         op-geth                                  │
│                                                                  │
│  Payload building                                                │
│  - validates fork gating for VRF payload attributes              │
│  - includes VRF fields in payload ID                             │
│  - injects public-key sync deposit                               │
│  - injects randomness commitment deposit                         │
│                                                                  │
│  EVM                                                             │
│  - EnshrainedVRF predeploy at 0x42...f0                          │
│  - ECVRF verify precompile at 0x0101                             │
└──────────────────────────────┬───────────────────────────────────┘
                               │ L2 execution
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                       L2 Contracts                               │
│                                                                  │
│  EnshrainedVRF                                                   │
│  - setSequencerPublicKey(bytes)   system deposit only            │
│  - commitRandomness(n, seed, beta, pi) system deposit only       │
│  - getRandomness() returns keccak256(beta || callCounter)        │
│  - getResult(n) returns historical seed, beta, pi                │
│                                                                  │
│  User contracts call getRandomness() synchronously in tx flow.   │
└──────────────────────────────────────────────────────────────────┘
```

## 2. Per-Block Lifecycle

```text
op-node                         op-geth                         EnshrainedVRF
-------                         -------                         ------------
  │                                │                                  │
  │ 1. Load SystemConfig           │                                  │
  │    vrfPublicKey from L1        │                                  │
  │                                │                                  │
  │ 2. Compute seed                │                                  │
  │    seed = SHA256(uint256(blockNumber) || uint256(nonce))         │
  │                                │                                  │
  │ 3. Prove with local/TEE prover │                                  │
  │    (beta, pi) = Prove(seed)    │                                  │
  │                                │                                  │
  │ 4. Send PayloadAttributes      │                                  │
  │ ──────────────────────────────▶│                                  │
  │    vrfPublicKey, seed,         │                                  │
  │    beta, pi, nonce             │                                  │
  │                                │                                  │
  │                                │ 5. Deposit setSequencerPublicKey │
  │                                │ ────────────────────────────────▶│
  │                                │                                  │
  │                                │ 6. Deposit commitRandomness      │
  │                                │ ────────────────────────────────▶│
  │                                │    Stores seed, beta, pi         │
  │                                │    Resets callCounter            │
  │                                │                                  │
  │                                │ 7. Execute user transactions     │
  │                                │ ────────────────────────────────▶│
  │                                │    getRandomness()               │
  │                                │    keccak256(beta || counter++)  │
```

The public-key deposit is emitted when a non-empty L1 `vrfPublicKey` is available. The randomness deposit is emitted when op-node supplies `vrfSeed`, `vrfProofBeta`, `vrfProofPi`, and `vrfNonce`.

## 3. Wire Formats

### Engine API PayloadAttributes

| JSON field | Type | Encoding | Required after fork |
|------------|------|----------|---------------------|
| `vrfPublicKey` | bytes | hex string | Optional, but required operationally for public verification |
| `vrfSeed` | bytes32 | hex string | Required when committing randomness |
| `vrfProofBeta` | bytes32 | hex string | Required when committing randomness |
| `vrfProofPi` | bytes | hex string, 81 bytes | Required when committing randomness |
| `vrfNonce` | uint64 | JSON number | Required when committing randomness |

These fields are included in op-geth payload ID derivation so concurrent payload builds with different VRF material cannot collide.

### Deposit Calldata

```solidity
setSequencerPublicKey(bytes pk)
commitRandomness(uint256 nonce, bytes32 seed, bytes32 beta, bytes pi)
```

Both deposits are sent from `DEPOSITOR_ACCOUNT`:

```text
0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001
```

Source hash domains are distinct from L1 info deposits and from each other:

| Domain | Deposit |
|--------|---------|
| `0x02` | VRF randomness commitment |
| `0x03` | VRF public-key sync |

### Verify Precompile

```text
Address: 0x0000000000000000000000000000000000000101
Input:   [33-byte pk][32-byte seed][32-byte beta][81-byte pi] = 178 bytes
Output:  0x01 for valid, 0x00 for invalid
Gas:     3,000
```

## 4. Storage Layout

`EnshrainedVRF` stores:

| Slot / structure | Value |
|------------------|-------|
| `_sequencerPublicKey` | 33-byte compressed SEC1 public key synced from L1 |
| `_commitNonce` | Next internal commitment nonce |
| `_currentBeta` | Beta committed for the current block |
| `_currentBlock` | L2 block number of the current commitment |
| `_callCounter` | Per-block randomness derivation counter |
| `_results[nonce]` | Historical `{ seed, beta, pi, blockNumber }` |

The external `nonce` parameter to `commitRandomness` is used for seed reconstruction and auditability. Storage is indexed by the contract's internal `_commitNonce`, which increments after every accepted commitment.

## 5. Fork Activation

```text
... -> Fjord -> Granite -> Holocene -> Isthmus -> Interop -> EnshrinedVRF
```

The fork is activated with:

| Config | Field |
|--------|-------|
| op-node rollup config | `enshrined_vrf_time` / `EnshrinedVRFTime` |
| op-geth chain config | `enshrinedVRFTime` / `EnshrinedVRFTime` |
| op-chain-ops deploy config | `l2GenesisEnshrinedVRFTimeOffset` |

If the fork is scheduled for a sequencer, op-node must be configured with either a local VRF key or a TEE endpoint. Startup fails when a sequencer has `EnshrainedVRFTime` configured but no prover.

## 6. Key Management

```text
1. Generate secp256k1 VRF keypair
   sk -> TEE/KMS/HSM boundary
   pk -> 33-byte compressed SEC1 public key

2. Register pk on L1
   SystemConfig.setVRFPublicKey(pk)
   emits ConfigUpdate(VRF_PUBLIC_KEY, abi.encode(pk))

3. op-node derives pk from L1 receipts
   eth.SystemConfig.VRFPublicKey = pk

4. op-geth syncs pk to L2
   deposit: EnshrainedVRF.setSequencerPublicKey(pk)

5. Verifiers read pk from L2 or L1 and verify (pk, seed, beta, pi)
```

Local mode keeps `sk` in op-node memory and is only suitable for development. Production mode should use `--sequencer.vrf-mode=tee` so op-node can request proofs without reading the secret key.

## 7. Verification and Fault-Proof Boundary

`EnshrainedVRF.commitRandomness` validates only the caller and proof length. It does not execute ECVRF verification during normal block execution.

Correctness is verified outside the commit path:

- `0x0101` verifies `(pk, seed, beta, pi)` on L2.
- `contracts/src/L1/VRFVerifier.sol` verifies seed construction and proof structure for dispute tooling.
- op-program routes the ECVRF precompile through its preimage-oracle-backed precompile path, so contracts that call `0x0101` can be re-executed in fault proofs.

Operationally, the L1 `SystemConfig` public key must match the active op-node prover key before production use. The Sepolia devnet scripts enforce the Sepolia chain-id guard and register the derived VRF public key during prepare.
