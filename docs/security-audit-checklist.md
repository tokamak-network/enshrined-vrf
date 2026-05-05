# Enshrined VRF Security Audit Checklist

**Date**: 2026-05-05
**Status**: Pre-audit

This checklist targets the current implementation described in [op-stack-customizations.md](op-stack-customizations.md).

## 1. Cryptographic Implementation

### ECVRF-SECP256K1-SHA256-TAI (`crypto/ecvrf/`, `op-geth/crypto/ecvrf/`)

- [ ] RFC 9381 flow is followed for prove, verify, and proof-to-hash.
- [ ] `suite_string` is consistently `0xFE`.
- [ ] try-and-increment encode-to-curve includes suite string, public key, alpha, counter, and separator bytes in the expected order.
- [ ] challenge generation hashes `(Y, H, Gamma, U, V)` in the documented order.
- [ ] proof-to-hash computes `SHA256(suite_string || 0x03 || Gamma || 0x00)`.
- [ ] RFC6979 nonce generation is deterministic and secret-key dependent.
- [ ] scalar operations use `ModNScalar`; secret scalar handling avoids `big.Int`.
- [ ] proof decoding rejects invalid compressed points and `s >= N`.
- [ ] independent test vectors or a second implementation have been used for cross-validation.

## 2. L2 Predeploy

### `EnshrainedVRF` (`optimism/packages/contracts-bedrock/src/L2/EnshrainedVRF.sol`)

- [ ] `commitRandomness(uint256,bytes32,bytes32,bytes)` is callable only by `DEPOSITOR_ACCOUNT`.
- [ ] `setSequencerPublicKey(bytes)` is callable only by `DEPOSITOR_ACCOUNT`.
- [ ] `setSequencerPublicKey` enforces a 33-byte compressed SEC1 key.
- [ ] `commitRandomness` enforces an 81-byte proof.
- [ ] `_commitNonce` increments exactly once for each accepted commitment.
- [ ] The external `nonce` parameter is documented as seed/audit material; storage uses internal `_commitNonce`.
- [ ] `_callCounter` resets on each commitment and increments on every `getRandomness()`.
- [ ] `getRandomness()` reverts when `_currentBlock != block.number`.
- [ ] No external calls are made from state-mutating functions.
- [ ] Storage layout is compatible with predeploy genesis allocation and future upgrades.
- [ ] Events are emitted for randomness commits and public-key updates.

## 3. L1 `SystemConfig` Extension

- [ ] `VRF_PUBLIC_KEY_SLOT = bytes32(uint256(keccak256("systemconfig.vrfpublickey")) - 1)` does not collide with existing slots.
- [ ] `setVRFPublicKey(bytes)` is `onlyOwner`.
- [ ] 33-byte key length is enforced.
- [ ] The first 32 bytes and final byte are stored and reconstructed exactly.
- [ ] The emitted `ConfigUpdate(VERSION, UpdateType.VRF_PUBLIC_KEY, abi.encode(pk))` payload matches op-node parsing.
- [ ] Empty key behavior is intentional and documented.

## 4. Fork Activation

- [ ] `EnshrainedVRFTime` is ordered after Interop in op-node fork metadata.
- [ ] op-geth `ChainConfig` exposes `EnshrainedVRFTime` and `IsEnshrainedVRF`.
- [ ] op-node rollup config exposes `enshrined_vrf_time`.
- [ ] op-chain-ops deploy config exposes `l2GenesisEnshrinedVRFTimeOffset`.
- [ ] `0x0101` is active only when EnshrainedVRF rules are active.
- [ ] `0x42...f0` predeploy code is present in EnshrainedVRF genesis allocs.
- [ ] Pre-fork payload attributes with VRF fields are rejected where applicable.

## 5. Derivation and Engine API

- [ ] op-node parses `SystemConfigUpdateVRFPublicKey` as a dynamic bytes wrapper around `abi.encode(bytes pk)`.
- [ ] op-node rejects malformed VRF public-key event payloads, non-empty padding, and invalid key lengths.
- [ ] `ComputeVRFSeed(blockNumber, nonce)` uses `SHA256(uint256(blockNumber) || uint256(nonce))` with 32-byte big-endian values.
- [ ] op-node fills `vrfSeed`, `vrfProofBeta`, `vrfProofPi`, and `vrfNonce` only when a prover is configured.
- [ ] A sequencer with `EnshrinedVRFTime` configured fails startup if no VRF prover is configured.
- [ ] TEE proof failures are retried and all-retry failure halts block production.
- [ ] VRF fields are preserved in singular batches, span batches, channel output, and attributes queue recovery.
- [ ] VRF byte fields marshal as JSON hex, not base64, in both op-service and op-geth Engine API types.

## 6. Block Building

- [ ] op-geth includes `vrfPublicKey`, `vrfSeed`, `vrfProofBeta`, `vrfProofPi`, and `vrfNonce` in payload ID derivation.
- [ ] Public-key sync deposit uses `setSequencerPublicKey(bytes)` and source-hash domain `0x03`.
- [ ] Randomness commit deposit uses `commitRandomness(uint256,bytes32,bytes32,bytes)` and source-hash domain `0x02`.
- [ ] Deposit calldata ABI encoding is tested against Solidity ABI expectations.
- [ ] VRF deposits are inserted after forced payload transactions and before txpool transactions.
- [ ] op-geth never receives or stores the VRF secret key.
- [ ] Missing or malformed randomness proof attributes cannot silently create malformed deposits.

## 7. Verification and Fault-Proof Boundary

- [ ] The audit model explicitly recognizes that `commitRandomness` does not run ECVRF verification during normal execution.
- [ ] Consumers, monitors, or dispute tooling can reconstruct `(pk, seed, beta, pi)` from L1/L2 state.
- [ ] L2 `0x0101` returns `0x01` only for a valid `(pk, seed, beta, pi)` tuple.
- [ ] op-program routes `0x0101` through the preimage-oracle-backed precompile path.
- [ ] L1 `VRFVerifier` documentation remains honest: it verifies seed construction and proof structure / proof-to-hash, not full EC verification.
- [ ] Operational policy requires L1 `SystemConfig.vrfPublicKey()` to match the active TEE/local prover public key before production use.

## 8. Threat Model

| Vector | Current mitigation | Audit focus |
|--------|--------------------|-------------|
| Sequencer predicts future randomness | Production mode keeps `sk` inside TEE | Verify TEE attestation and key sealing |
| Local dev key used in production | CLI exposes local mode but documents it as dev only | Deployment policy and configuration checks |
| Wrong public key registered on L1 | Verification script checks L2 key matches L1 key; operators must match prover key | Add operational runbook / monitoring |
| Wrong seed committed | Seed is stored and reconstructable from block number and nonce | Challenge tooling must check it |
| Invalid beta/proof committed | Tuple can be verified with `0x0101` or dispute tooling | Ensure monitoring/challenge path is complete |
| Missing commitment | op-node requires prover for scheduled fork; proof failures halt block production | Verify follower/reorg behavior and monitoring |
| Payload ID collision | VRF fields included in payload ID | Test all fields independently affect ID |
| Deposit source hash collision | VRF domains `0x02` and `0x03` are distinct | Verify no collision with OP Stack deposit domains |

## 9. Test Coverage to Run Before Audit

| Component | Command |
|-----------|---------|
| Root ECVRF | `go test ./crypto/ecvrf/ -v` |
| Root contracts | `cd contracts && forge test --match-contract EnshrainedVRFTest -v && forge test --match-contract VRFVerifierTest -v` |
| op-geth precompile | `cd op-geth && go test ./core/vm/ -run ECVRF -v` |
| op-geth Engine API | `cd op-geth && go test ./beacon/engine/ -run VRF -v` |
| op-geth miner | `cd op-geth && go test ./miner/ -run 'VRF|PayloadIdIncludesVRFAttributes' -v` |
| op-service JSON | `cd optimism && go test ./op-service/eth -run VRF -v` |
| op-node derivation | `cd optimism && go test ./op-node/rollup/derive -run 'VRF|SystemConfig|PreparePayloadAttributes' -v` |
| Sepolia local L2 | `./scripts/devnet-sepolia-verify-random.sh` |

## 10. Recommended External Audit Focus

1. ECVRF cryptographic correctness and independent cross-validation.
2. TEE key lifecycle, attestation, sealing, and production configuration.
3. OP Stack derivation determinism across singular/span batches.
4. Engine API payload attribute encoding and payload ID uniqueness.
5. Deposit calldata/source-hash domains and ordering.
6. Verification and dispute story for invalid `(pk, seed, beta, pi)` tuples.
