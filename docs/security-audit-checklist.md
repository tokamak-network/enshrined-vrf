# Enshrined VRF — Security Audit Checklist

**Date**: 2026-04-03  
**Status**: Pre-audit

---

## 1. Cryptographic Implementation (CRITICAL)

### ECVRF-SECP256K1-SHA256-TAI (`crypto/ecvrf/`)

- [ ] **RFC 9381 Compliance**: Verify algorithm matches RFC 9381 sections 5.1-5.4
- [ ] **encode_to_curve_TAI**: Confirm try-and-increment implementation is correct
  - Counter range [0, 255)
  - SHA-256 hash includes suite_string, 0x01, PK, alpha, ctr, 0x00
  - Even y-coordinate (0x02 prefix)
- [ ] **challenge_generation**: 5-point hash with correct ordering (Y, H, Gamma, U, V)
- [ ] **proof_to_hash**: SHA-256(suite_string || 0x03 || cofactor*Gamma || 0x00)
  - Cofactor = 1 for secp256k1 (no cofactor multiplication needed)
- [ ] **Nonce generation**: RFC 6979 via `secp256k1.NonceRFC6979`
- [ ] **Scalar arithmetic**: All operations use `ModNScalar` (constant-time)
- [ ] **Secret key zeroization**: `sk.Key.Bytes()` zeroed after use
- [ ] **Nonce `k` zeroization**: `k.Zero()` called after use
- [ ] **No timing side channels**: No branch on secret data, no big.Int for secret scalars
- [ ] **Proof validation**: `s < N` check in `decodeProof` via `SetByteSlice` overflow

### Cross-validation

- [ ] **Known test vector**: Verify against independent ECVRF implementation (Python/Rust)
- [ ] **Solidity consistency**: `proofToHash` in VRFVerifier.sol matches Go `ProofToHash`

---

## 2. Smart Contracts (HIGH)

### PredeployedVRF (`contracts/src/PredeployedVRF.sol`)

- [ ] **Access control**: Only `DEPOSITOR_ACCOUNT` can call `commitRandomness` and `setSequencerPublicKey`
- [ ] **Nonce monotonicity**: `_commitNonce` strictly increments, `NonceMismatch` on skip
- [ ] **No reentrancy**: No external calls in `getRandomness()` or `commitRandomness()`
- [ ] **Storage layout**: No collisions between `_nonce`, `_sequencerPublicKey`, `_results` mapping
- [ ] **Proof length validation**: `pi.length == 81` enforced
- [ ] **Public key length validation**: `pk.length == 33` enforced
- [ ] **Consume nonce overflow**: `unchecked { _consumeNonce++ }` — safe if nonce < 2^256
- [ ] **Event emission**: Events emitted for all state changes

### VRFVerifier (`contracts/src/L1/VRFVerifier.sol`)

- [ ] **Honest documentation**: Contract clearly states it only performs proof-to-hash check
- [ ] **No false security claims**: Full EC verification is NOT performed
- [ ] **Input validation**: PK length (33), pi length (81), s < N
- [ ] **Pure functions**: No state modifications, safe for arbitrary callers

### SystemConfig VRF Extension

- [ ] **Storage slot**: `VRF_PUBLIC_KEY_SLOT = keccak256("systemconfig.vrfpublickey") - 1`
- [ ] **No slot collision**: Verify against existing SystemConfig storage slots
- [ ] **Owner-only setter**: `onlyOwner` modifier on `setVRFPublicKey`
- [ ] **33-byte validation**: `_vrfPublicKey.length == 33` enforced
- [ ] **2-slot encoding**: First 32 bytes in `VRF_PUBLIC_KEY_SLOT`, last byte in `VRF_PUBLIC_KEY_SLOT + 1`

---

## 3. Protocol Integration (HIGH)

### Fork Activation

- [ ] **Fork ordering**: EnshrainedVRF comes after Interop in `forks.All`
- [ ] **ChainConfig**: `EnshrainedVRFTime` in op-geth `params/config.go`
- [ ] **Rollup Config**: `EnshrainedVRFTime` in `op-node/rollup/types.go`
- [ ] **Rules struct**: `IsOptimismEnshrainedVRF` propagated correctly
- [ ] **Precompile gating**: `PrecompiledContractsEnshrainedVRF` only active when fork is active

### Derivation Pipeline

- [ ] **VRF public key propagation**: L1 SystemConfig → op-node → PayloadAttributes → op-geth
- [ ] **SystemConfig event parsing**: `SystemConfigUpdateVRFPublicKey` (type 8) correctly parsed
- [ ] **Deposit tx creation**: VRF deposit txs use correct ABI encoding
- [ ] **Source hash uniqueness**: VRF deposit source hash is distinct from L1Info deposits

### Block Building

- [ ] **Sequencer-only**: VRF prove only called in sequencer mode
- [ ] **Deposit tx ordering**: VRF deposit tx injected after L1Info deposit, before user txs
- [ ] **Seed construction**: `sha256(blockNumber, nonce)` matches spec
- [ ] **Private key isolation**: SK never in calldata, storage, or EVM trace
- [ ] **Failure handling**: VRF prove failure retried (default 3 attempts, 100ms interval); all retries exhausted → block production halted (safety over liveness)

---

## 4. Fault Proof Compatibility (MEDIUM)

- [ ] **Deterministic re-execution**: Deposit tx with (nonce, beta, pi) produces identical state
- [ ] **Precompile in op-program**: ECVRF verify precompile included in fault proof VM
- [ ] **State root consistency**: Block with VRF deposits produces same state root on re-execution
- [ ] **Seed verifiability**: Seed can be reconstructed from `sha256(blockNumber, nonce)`

---

## 5. Threat Model

### Sequencer Manipulation Vectors

| Vector | Mitigation | Status |
|--------|-----------|--------|
| Choose favorable VRF output | TEE-protected sk prevents sequencer from computing VRF outputs | ✅ |
| Skip VRF commitment | Nonce gap detected by verifiers | ✅ |
| Reorder txs to front-run randomness | Randomness committed in deposit tx before user txs | ✅ |
| Use wrong seed | Seed verifiable from L1 data via VRFVerifier.verifySeed() | ✅ |
| Leak VRF private key | SK never enters EVM; held in Go memory only | ✅ |

### Attack Surfaces

| Surface | Risk | Notes |
|---------|------|-------|
| ECVRF algorithm bug | High | Needs independent verification against reference impl |
| PredeployedVRF storage collision | Medium | Standard Solidity layout, no assembly tricks |
| SystemConfig storage slot overlap | Medium | Named slots with keccak256 |
| Deposit tx malformation | Low | ABI encoding is straightforward |
| Timing attack on Prove | Low | ModNScalar is constant-time; Prove runs off-chain |

---

## 6. Test Coverage Summary

| Component | Tests | Fuzz | Coverage |
|-----------|-------|------|----------|
| ECVRF Go library | 22 | 164K+ iterations | Core algorithm |
| ECVRF Verify precompile | 9 | — | All input variants |
| PredeployedVRF | 31 | — | All functions + edge cases |
| VRFVerifier | 20 | 256 runs | All functions + known vector |
| **Total** | **82** | **164K+** | — |

---

## 7. Recommended External Audit Focus

1. **ECVRF cryptographic correctness** (highest priority)
   - Cross-validate with independent implementation
   - Verify no subtle bugs in EC point arithmetic
   
2. **PredeployedVRF access control and storage**
   - Verify DEPOSITOR_ACCOUNT checks
   - Storage layout collision analysis
   
3. **Seed construction and TEE security**
   - Seed is deterministic (`sha256(blockNumber)`) — unpredictability relies on TEE-protected sk
   - Confirm TEE attestation chain is valid

4. **Fault proof integration**
   - Verify deposit tx re-execution determinism
   - Test with Cannon/Asterisc
