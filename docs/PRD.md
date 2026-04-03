# Enshrined VRF — Product Requirements Document

**Version**: 2.0  
**Date**: 2026-04-02  
**Status**: Implementation Ready  
**Owner**: Protocol Engineering  
**Priority**: P0

---

## 1. Problem Statement

현재 OP Stack L2에서 컨트랙트가 검증 가능한 난수를 얻으려면 Chainlink VRF 같은 외부 오라클에 의존해야 하며, 이는 비동기 콜백(2+ 트랜잭션), 추가 비용, 외부 의존성을 수반한다.

**Enshrined VRF**는 ECVRF precompile을 프로토콜 레벨에 내장하여, 컨트랙트가 **동일 트랜잭션 내에서 동기적으로** 검증 가능한 난수를 받을 수 있게 한다.

---

## 2. Goals & Non-Goals

### Goals
- L2 컨트랙트가 단일 함수 호출로 검증 가능한 난수 획득
- Sequencer 단독 조작 불가 (L1 RANDAO를 seed에 포함)
- 누구나 VRF 결과를 온체인에서 검증 가능
- Fault proof와 완전 호환
- 기존 OP Stack과 하위 호환 (fork 활성화 방식)

### Non-Goals
- 다중 sequencer 환경 지원 (향후 확장)
- VRF 키 로테이션 자동화 (수동 SystemConfig 업데이트)
- L1에서의 VRF 사용 (L2 전용)

---

## 3. Architecture

### 3.1 High-Level Data Flow

```
┌─────────────┐         ┌──────────────┐         ┌──────────────────────┐
│   L1 Block  │         │   op-node    │         │      op-geth         │
│  (RANDAO)   │────────▷│  Derivation  │────────▷│  Block Building      │
│             │         │  Pipeline    │         │                      │
└─────────────┘         └──────────────┘         │  1. Read prevrandao  │
                                                  │  2. ecvrf.Prove()    │
                                                  │  3. Inject deposit tx│
                                                  └──────────┬───────────┘
                                                             │
                                                             ▼
                                                  ┌──────────────────────┐
                                                  │   PredeployedVRF     │
                                                  │   (0x42...F0)        │
                                                  │                      │
                                                  │  commitRandomness()  │
                                                  │  getRandomness()     │
                                                  │  getResult()         │
                                                  └──────────────────────┘
                                                             │
                                                             ▼
                                                  ┌──────────────────────┐
                                                  │   User Contract      │
                                                  │   (e.g. CoinFlip)    │
                                                  └──────────────────────┘
```

### 3.2 Design Decision: Prove vs Verify Precompile

원래 스펙에서는 Prove를 EVM precompile로 실행하도록 기술했으나, 다음 두 가지 문제로 인해 아키텍처를 조정한다:

| 문제 | 설명 | 해결 |
|------|------|------|
| 비밀키 노출 | Prove precompile에 SK 전달 시 EVM trace에 노출 | Go 라이브러리에서 Prove 실행 |
| 재실행 불가 | Fault proof 시 verifier에 SK 없음 | Deposit tx로 결과 커밋, 재실행 시 동일 결과 재생 |

**최종 아키텍처**:
- **Prove**: Go 라이브러리 (`crypto/ecvrf`) — sequencer가 블록 빌딩 시 호출
- **Verify**: EVM Precompile (`0x0101`) — 누구나 온체인에서 검증 가능
- **결과 전달**: System deposit transaction으로 `PredeployedVRF.commitRandomness()` 호출

### 3.3 Component Map

| Layer | Component | Repository | Change Type |
|-------|-----------|------------|-------------|
| Cryptography | ECVRF-SECP256K1-SHA256-TAI | op-geth | New package |
| Execution | ECVRF Verify Precompile | op-geth | New precompile |
| Execution | Fork activation | op-geth | Config change |
| L2 Contract | PredeployedVRF | optimism | New predeploy |
| Derivation | PayloadAttributes extension | optimism | Modification |
| Derivation | VRF deposit tx injection | optimism | New logic |
| L1 Contract | SystemConfig VRF key mgmt | optimism | Modification |
| Fault Proof | op-program ECVRF support | optimism | Dependency |

### 3.4 Seed Construction

```
seed = keccak256(abi.encodePacked(prevrandao, block.number, nonce))
```

| Field | Source | Role |
|-------|--------|------|
| `sequencer_sk` | Sequencer KMS/HSM | ECVRF 비밀키 |
| `prevrandao` | L1 Derivation Pipeline (mixHash) | 외부 엔트로피 (sequencer 단독 조작 불가) |
| `block.number` | L2 블록 생성 | 블록별 고유성 |
| `nonce` | PredeployedVRF 내부 카운터 | 호출별 고유성 |

---

## 4. Interfaces

### 4.1 PredeployedVRF (L2)

**Address**: `0x42000000000000000000000000000000000000F0`

```solidity
interface IEnshrainedVRF {
    /// @notice Emitted when new randomness is committed by the sequencer
    event RandomnessCommitted(uint256 indexed nonce, bytes32 beta, bytes pi);

    /// @notice Returns the next available random value for the current block
    /// @dev Increments internal nonce, reads from committed randomness
    /// @return randomness The VRF output (beta) as uint256
    function getRandomness() external returns (uint256 randomness);

    /// @notice Retrieves a historical VRF result by nonce
    /// @param nonce The nonce of the desired result
    /// @return beta The VRF output hash
    /// @return pi The VRF proof (81 bytes)
    function getResult(uint256 nonce) external view returns (uint256 beta, bytes memory pi);

    /// @notice Returns the sequencer's VRF public key
    /// @return pk Compressed SEC1 public key (33 bytes)
    function sequencerPublicKey() external view returns (bytes memory pk);
}
```

**System-only functions** (callable by DEPOSITOR_ACCOUNT `0xDeaD...0001`):

```solidity
/// @notice Commits VRF randomness for the current block (system deposit tx)
function commitRandomness(uint256 nonce, bytes32 beta, bytes calldata pi) external;

/// @notice Updates the sequencer's VRF public key (from L1 SystemConfig)
function setSequencerPublicKey(bytes calldata pk) external;
```

### 4.2 ECVRF Verify Precompile

**Address**: `0x0101` (OP Stack extended precompile range)

```
Input:  [33 bytes PK][32 bytes alpha/seed][32 bytes beta][81 bytes pi] = 178 bytes
Output: [1 byte: 0x01 valid / 0x00 invalid]
Gas:    3,000
```

### 4.3 SystemConfig (L1)

```solidity
/// @notice Sets the sequencer's VRF public key (owner only)
function setVRFPublicKey(bytes calldata pk) external;

/// @notice Returns the current VRF public key
function vrfPublicKey() external view returns (bytes memory);

/// @notice Emitted when VRF public key is updated
event VRFPublicKeyUpdated(bytes pk);
```

### 4.4 ECVRF Go Library

```go
package ecvrf

// Prove computes VRF output and proof for the given secret key and alpha string.
func Prove(sk *secp256k1.PrivateKey, alpha []byte) (beta [32]byte, pi [81]byte, err error)

// Verify checks VRF proof against public key and alpha string.
func Verify(pk *secp256k1.PublicKey, alpha []byte, pi [81]byte) (valid bool, beta [32]byte, err error)

// ProofToHash extracts VRF hash output (beta) from a valid proof.
func ProofToHash(pi [81]byte) (beta [32]byte, err error)
```

---

## 5. ECVRF Algorithm Specification

### 5.1 Suite Parameters

Based on RFC 9381 with secp256k1 curve:

| Parameter | Value |
|-----------|-------|
| `suite_string` | `0xFE` (custom suite) |
| EC Group | secp256k1 (`y^2 = x^3 + 7`, `p = 2^256 - 2^32 - 977`) |
| Cofactor | 1 |
| Hash | SHA-256 |
| `encode_to_curve` | try_and_increment (TAI) |
| `ptLen` | 33 bytes (SEC1 compressed) |
| `cLen` | 16 bytes (challenge truncation) |
| `qLen` | 32 bytes (curve order) |
| Proof (`pi`) size | 81 bytes (`ptLen + cLen + qLen`) |
| Output (`beta`) size | 32 bytes |

### 5.2 Key Operations

1. **ECVRF_encode_to_curve_try_and_increment(suite_string, Y, alpha_string)**
   - Hash-to-curve via iterative hashing until a valid x-coordinate is found
2. **ECVRF_nonce_generation_RFC6979(SK, h_string)**
   - Deterministic nonce per RFC 6979
3. **ECVRF_challenge_generation(Y, H, Gamma, U, V)**
   - Hash of five EC points to produce challenge scalar
4. **ECVRF_prove(SK, alpha_string)** → `pi_string`
5. **ECVRF_verify(Y, pi_string, alpha_string)** → `("VALID", beta_string)` or `"INVALID"`
6. **ECVRF_proof_to_hash(pi_string)** → `beta_string`

### 5.3 Determinism Guarantee

동일한 `(sk, alpha)` 입력은 항상 동일한 `(beta, pi)`를 생성한다. 이는 프로토콜의 핵심 속성으로, fault proof 검증의 기반이 된다.

---

## 6. Fork Activation

| Field | Type | Description |
|-------|------|-------------|
| `EnshrainedVRFTime` | `*uint64` | Unix timestamp for fork activation |

- op-geth `ChainConfig`와 optimism `rollup.Config` 모두에 추가
- 기존 최신 fork (Interop/Karst) 이후에 배치
- `nil`이면 비활성, timestamp 이후 활성

---

## 7. Security Considerations

### 7.1 Sequencer Manipulation Resistance

- **prevrandao**: L1에서 유래하므로 sequencer가 단독 조작 불가
- **block.number**: L2 블록 높이, 조작 불가
- **nonce**: 순차 증가, 스킵 불가 (fault proof로 검증)
- Sequencer가 조작할 수 있는 것: 특정 블록에서 VRF 호출을 포함/제외하는 것 (트랜잭션 검열). 이는 일반적인 sequencer 검열 문제와 동일하며 별도 메커니즘으로 대응.

### 7.2 Private Key Security

- VRF 비밀키는 EVM에 절대 노출되지 않음 (Go 레벨에서만 사용)
- KMS/HSM 지원 가능한 구조
- EVM trace, calldata, 스토리지 어디에도 SK 미포함

### 7.3 Fault Proof Compatibility

- VRF 결과가 deposit tx로 커밋되므로 재실행 시 동일 결과 재생
- 위반 검증: L1에서 verify precompile 또는 Solidity ECVRF verify로 `(pk, seed, beta, pi)` 검증
- 검증 가능 위반 유형:
  - 잘못된 `beta`/`pi`: `ECVRF.Verify(pk, seed, beta, pi)` 실패
  - 잘못된 `seed`: L1 데이터로 seed 재구성 후 불일치 확인
  - `nonce` 조작: 순차 nonce 검증

---

## 8. Gas & Performance

| Metric | Target | Measurement Method |
|--------|--------|--------------------|
| Precompile latency (verify) | ≤ 0.3ms | Go benchmark |
| Prove latency (Go library) | ≤ 0.3ms | Go benchmark |
| Gas cost (verify) | 3,000 | Calibrated to actual compute |
| TPS impact | ≤ 1% | Devnet load test |
| Verification success rate | 100% | Test suite |
| Fault proof detection rate | 100% | Test suite |

---

## 9. Milestones & Acceptance Criteria

### Phase 0: Repository Setup
**Deliverable**: Forked submodules, build scripts  
**Acceptance**:
- [ ] `make build` succeeds for both op-geth and optimism
- [ ] Submodules point to correct upstream branches

### Phase 1: ECVRF Library + Verify Precompile
**Deliverable**: `crypto/ecvrf` package, `ecvrfVerify` precompile  
**Acceptance**:
- [ ] `Prove` → `Verify` round-trip passes for 1000+ random keys
- [ ] Tampered proof rejection: 100% (bit-flip, wrong key, wrong alpha)
- [ ] Determinism: same `(sk, alpha)` → same `(beta, pi)` across 10000 runs
- [ ] Benchmark: Prove ≤ 0.3ms, Verify ≤ 0.3ms (on target hardware)
- [ ] Go fuzz test: 0 crashes after 10M+ iterations
- [ ] Precompile gas cost calibrated within 10% of benchmark
- [ ] Fork activation gating works correctly
- [ ] Phase 1 completion report (`docs/phase-1-report.md`)

### Phase 2: PredeployedVRF Contract
**Deliverable**: Solidity predeploy contract  
**Acceptance**:
- [ ] `commitRandomness` only callable by DEPOSITOR_ACCOUNT
- [ ] `setSequencerPublicKey` only callable by DEPOSITOR_ACCOUNT
- [ ] `getRandomness` returns committed value correctly
- [ ] `getResult` returns historical values
- [ ] Nonce monotonically increases
- [ ] Events emitted correctly
- [ ] Genesis registration works
- [ ] Phase 2 completion report (`docs/phase-2-report.md`)

### Phase 3: Derivation Pipeline
**Deliverable**: L1 RANDAO forwarding, VRF deposit tx injection  
**Acceptance**:
- [ ] PayloadAttributes includes VRF public key
- [ ] Sequencer builds blocks with VRF deposit tx
- [ ] VRF deposit tx contains correct `(nonce, beta, pi)`
- [ ] Seed constructed from correct `(prevrandao, block.number, nonce)`
- [ ] Follower nodes accept and verify VRF deposit txs
- [ ] Phase 3 completion report (`docs/phase-3-report.md`)

### Phase 4: L1 Contracts & Fault Proof
**Deliverable**: SystemConfig VRF key management, fault proof integration  
**Acceptance**:
- [ ] SystemConfig owner can set/get VRF public key
- [ ] VRF public key changes propagate to L2 via derivation
- [ ] Fault proof re-execution produces identical state
- [ ] Invalid VRF results are detectable and provable on L1
- [ ] Phase 4 completion report (`docs/phase-4-report.md`)

---

## 10. Usage Example

```solidity
contract CoinFlip {
    IEnshrainedVRF constant VRF = IEnshrainedVRF(
        0x42000000000000000000000000000000000000F0
    );

    event FlipResult(address indexed player, bool heads);

    function flip() external returns (bool heads) {
        uint256 randomness = VRF.getRandomness();
        heads = (randomness % 2 == 0);
        emit FlipResult(msg.sender, heads);
    }
}
```

---

## Appendix A: File Change Summary

### op-geth (New/Modified)
| File | Type | Description |
|------|------|-------------|
| `crypto/ecvrf/ecvrf.go` | New | ECVRF core algorithm |
| `crypto/ecvrf/params.go` | New | Suite constants |
| `crypto/ecvrf/ecvrf_test.go` | New | Unit tests + fuzz + benchmark |
| `core/vm/contracts_ecvrf.go` | New | Verify precompile |
| `core/vm/contracts_ecvrf_test.go` | New | Precompile tests |
| `core/vm/contracts.go` | Mod | Register precompile in fork map |
| `params/config.go` | Mod | EnshrainedVRFTime fork config |
| `params/protocol_params.go` | Mod | Gas constants |
| `miner/worker.go` | Mod | VRF prove + deposit tx injection |
| `core/vm/evm.go` | Mod | BlockContext VRF fields |

### optimism monorepo (New/Modified)
| File | Type | Description |
|------|------|-------------|
| `packages/contracts-bedrock/src/L2/PredeployedVRF.sol` | New | Predeploy contract |
| `packages/contracts-bedrock/src/L2/interfaces/IEnshrainedVRF.sol` | New | Interface |
| `packages/contracts-bedrock/test/L2/PredeployedVRF.t.sol` | New | Contract tests |
| `packages/contracts-bedrock/src/libraries/Predeploys.sol` | Mod | Address registration |
| `packages/contracts-bedrock/src/L1/SystemConfig.sol` | Mod | VRF key management |
| `op-node/rollup/types.go` | Mod | Fork config |
| `op-node/rollup/derive/attributes.go` | Mod | PayloadAttributes |
| `op-node/rollup/derive/l1_block_info.go` | Mod | VRF deposit tx |
| `op-service/eth/types.go` | Mod | PayloadAttributes fields |
| `op-chain-ops/genesis/` | Mod | Genesis allocs |
