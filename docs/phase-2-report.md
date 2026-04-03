# Phase 2 Completion Report — PredeployedVRF Contract

**Date**: 2026-04-02  
**Status**: Complete

---

## 1. Deliverables

### Solidity Contracts

| File | Description |
|------|-------------|
| `contracts/src/interfaces/IEnshrainedVRF.sol` | Public interface: getRandomness, getResult, sequencerPublicKey, commitNonce |
| `contracts/src/PredeployedVRF.sol` | Full implementation with access control, storage, events |
| `contracts/test/PredeployedVRF.t.sol` | 31 Foundry test cases including integration test |

### Contract Details

| Property | Value |
|----------|-------|
| Address | `0x42000000000000000000000000000000000000f0` |
| Solidity Version | 0.8.28 |
| Access Control | DEPOSITOR_ACCOUNT (`0xDeaD...0001`) for system functions |
| Verify Precompile | `0x0101` (referenced, used in Phase 3+) |

### Storage Layout

| Slot | Type | Variable | Purpose |
|------|------|----------|---------|
| 0 | `bytes` | `_sequencerPublicKey` | Compressed SEC1 public key (33 bytes) |
| 1 | `uint256` | `_commitNonce` | Next commitment nonce |
| 2 | `uint256` | `_consumeNonce` | Next consumption nonce |
| 3+ | `mapping(uint256 => VrfResult)` | `_results` | Historical VRF results |

### Architecture: Dual-Nonce Design

스펙의 단일 nonce 설계를 **dual-nonce**로 개선:

- **`_commitNonce`**: Sequencer가 deposit tx로 결과를 커밋할 때 증가
- **`_consumeNonce`**: User가 `getRandomness()`를 호출할 때 증가

이를 통해:
1. Sequencer가 블록당 여러 VRF 결과를 미리 커밋 가능
2. 각 `getRandomness()` 호출이 고유한 결과를 반환
3. 결과 소진 시 명확한 에러 (`NoRandomnessAvailable`)

---

## 2. Test Results

### 31 Tests, All PASS

```
=== Access Control (5 tests) ===
test_setSequencerPublicKey_success              PASS
test_setSequencerPublicKey_revertNotDepositor    PASS
test_setSequencerPublicKey_revertInvalidLength   PASS
test_setSequencerPublicKey_revertInvalidLength65 PASS
test_commitRandomness_revertNotDepositor         PASS

=== Commit Randomness (5 tests) ===
test_commitRandomness_success                   PASS
test_commitRandomness_emitsEvent                PASS
test_commitRandomness_sequential                PASS
test_commitRandomness_revertNonceMismatch       PASS
test_commitRandomness_revertInvalidProofLength  PASS
test_commitRandomness_skipNonceReverts          PASS

=== Get Randomness (4 tests) ===
test_getRandomness_success                      PASS
test_getRandomness_sequential                   PASS
test_getRandomness_revertNoAvailable            PASS
test_getRandomness_revertExhausted              PASS
test_getRandomness_anyoneCanCall                PASS

=== Get Result (4 tests) ===
test_getResult_success                          PASS
test_getResult_historical                       PASS
test_getResult_revertNonceNotCommitted          PASS
test_getResult_revertFutureNonce                PASS
test_getResult_stillAvailableAfterConsume        PASS

=== State & Integration (6 tests) ===
test_initialState                               PASS
test_nonceTracking                              PASS
test_depositorAccountAddress                    PASS
test_ecvrfVerifyPrecompileAddress               PASS
test_setSequencerPublicKey_overwrite            PASS
test_coinFlipExample                            PASS

=== Batch & Gas (4 tests) ===
test_batchCommitAndConsume (50 items)            PASS
test_gasCommitRandomness                        PASS
test_gasGetRandomness                           PASS
test_gasGetResult                               PASS
```

---

## 3. Gas Costs

| Function | Gas Cost | Notes |
|----------|----------|-------|
| `commitRandomness` | ~164,834 | Storage write (SSTORE for beta, pi, blockNumber) |
| `getRandomness` | ~23,622 | Storage read + nonce increment |
| `getResult` | ~4,100 | View function, storage read only |
| `setSequencerPublicKey` | ~79,574 | First write (cold storage) |

`getRandomness`의 ~24K gas는 사용자 입장에서 매우 저렴 (Chainlink VRF callback 대비 ~90% 절감).

---

## 4. Security Properties

| Property | Enforcement | Test |
|----------|-------------|------|
| System-only commitment | `onlyDepositor` modifier | test_commitRandomness_revertNotDepositor |
| System-only key update | `onlyDepositor` modifier | test_setSequencerPublicKey_revertNotDepositor |
| Sequential nonce | `NonceMismatch` revert | test_commitRandomness_skipNonceReverts |
| Proof length validation | 81 bytes required | test_commitRandomness_revertInvalidProofLength |
| PK length validation | 33 bytes required | test_setSequencerPublicKey_revertInvalidLength |
| Exhaustion protection | `NoRandomnessAvailable` | test_getRandomness_revertExhausted |
| Historical immutability | Results persist after consume | test_getResult_stillAvailableAfterConsume |

---

## 5. Custom Errors

| Error | Trigger |
|-------|---------|
| `OnlyDepositor()` | Non-DEPOSITOR calls system function |
| `NoRandomnessAvailable()` | All committed randomness consumed |
| `NonceNotCommitted()` | Query for non-existent nonce |
| `NonceMismatch()` | Commitment nonce doesn't match expected |
| `InvalidPublicKeyLength()` | PK != 33 bytes |
| `InvalidProofLength()` | Proof != 81 bytes |

---

## 6. File Structure

```
contracts/
├── foundry.toml
├── lib/forge-std/          # Foundry standard library
├── src/
│   ├── interfaces/
│   │   └── IEnshrainedVRF.sol    # Public interface
│   └── PredeployedVRF.sol        # Implementation
└── test/
    └── PredeployedVRF.t.sol      # 31 test cases
```

---

## 7. Next Steps (Phase 3)

1. Derivation Pipeline 수정 (op-node):
   - `EnshrainedVRFTime` fork config
   - PayloadAttributes에 VRF public key 필드 추가
   - VRF deposit tx 생성 로직
2. Engine API (op-geth):
   - Sequencer 블록 빌딩 시 VRF 결과 계산 + deposit tx 주입
