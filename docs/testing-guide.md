# Enshrined VRF — Testing & Demo Guide

## 1. Unit Tests (즉시 실행 가능)

### Prerequisites

```bash
# Go 1.24+
go version

# Foundry (forge)
forge --version
```

### 1.1 ECVRF Go Library

```bash
# 전체 테스트 (22 tests)
go test ./crypto/ecvrf/ -v

# 벤치마크
go test ./crypto/ecvrf/ -bench=. -benchmem

# Fuzz 테스트 (30초)
go test ./crypto/ecvrf/ -fuzz=FuzzProveVerify -fuzztime=30s

# Fuzz 테스트 (랜덤 proof 거부 확인)
go test ./crypto/ecvrf/ -fuzz=FuzzVerifyRejectsRandom -fuzztime=30s
```

**기대 결과:**
- 22 tests PASS
- Prove: ~0.35ms, Verify: ~0.42ms
- Fuzz: 0 crashes

### 1.2 Verify Precompile (Standalone)

```bash
go test ./core/vm/ -v
```

**기대 결과:** 9 tests PASS

### 1.3 Solidity Contracts

```bash
cd contracts

# 전체 테스트
forge test -v

# 특정 컨트랙트만
forge test --match-contract EnshrainedVRFTest -v
forge test --match-contract VRFVerifierTest -v

# 가스 측정
forge test --match-test "test_gas" -vvv
```

**기대 결과:**
- EnshrainedVRFTest: 30 PASS
- VRFVerifierTest: 20 PASS
- getRandomness gas: ~24K
- commitRandomness gas: ~165K

### 1.4 op-geth 내부 테스트

```bash
cd op-geth

# ECVRF 라이브러리 (op-geth 모듈 내)
go test ./crypto/ecvrf/ -v

# 기존 precompile 테스트 포함 전체
go test ./core/vm/ -run "TestPrecompiled" -v
```

---

## 2. Devnet E2E Test (전체 플로우 검증)

### 2.1 Prerequisites

```bash
# Docker
docker --version

# Docker Compose
docker compose version

# Make / Just
make --version
# 또는
just --version
```

### 2.2 Devnet 설정

**Step 1: rollup config에 EnshrainedVRFTime 추가**

devnet의 rollup config에 fork 활성화 시간을 설정합니다. `0`으로 설정하면 genesis부터 활성화됩니다.

```bash
cd optimism

# devnet config 파일 찾기
find . -name "devnetL1-template.json" -o -name "devnet*.json" | head -5
```

rollup config JSON에 추가:
```json
{
  "enshrined_vrf_time": 0
}
```

op-geth chain config에도 추가:
```json
{
  "enshrainedVRFTime": 0
}
```

**Step 2: VRF Private Key 설정**

sequencer 시작 시 VRF private key를 환경변수로 전달합니다.
테스트용 키 (절대 프로덕션에서 사용하지 마세요):

```bash
export VRF_PRIVATE_KEY=c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721
```

해당 public key:
```
0x02b4632d08485ff1df2db55b9dafd23347d1c47a457072a1e87be26a2c20f4b524
```

**Step 3: Genesis 생성**

```bash
cd optimism/packages/contracts-bedrock

# Forge build (EnshrainedVRF.sol 포함)
forge build

# Genesis allocs 생성
just genesis
# 또는
forge script scripts/L2Genesis.s.sol:L2Genesis --sig 'runWithStateDump()'
```

**Step 4: L1에 VRF Public Key 등록**

```bash
# SystemConfig에 VRF public key 설정 (L1에서)
cast send <SYSTEM_CONFIG_ADDR> \
  "setVRFPublicKey(bytes)" \
  0x02b4632d08485ff1df2db55b9dafd23347d1c47a457072a1e87be26a2c20f4b524 \
  --rpc-url http://localhost:8546 \
  --private-key <OWNER_PRIVATE_KEY>
```

**Step 5: Devnet 시작**

```bash
cd optimism
make devnet-up
# 또는
just devnet-up
```

### 2.3 E2E 검증

devnet이 올라간 후:

**Check 1: EnshrainedVRF 컨트랙트 존재 확인**

```bash
cast code 0x42000000000000000000000000000000000000f0 --rpc-url http://localhost:8545
```

출력이 `0x`가 아닌 바이트코드가 나와야 합니다.

**Check 2: Sequencer Public Key 확인**

```bash
cast call 0x42000000000000000000000000000000000000f0 \
  "sequencerPublicKey()(bytes)" \
  --rpc-url http://localhost:8545
```

**Check 3: Commit Nonce 확인 (sequencer가 VRF를 커밋하고 있는지)**

```bash
cast call 0x42000000000000000000000000000000000000f0 \
  "commitNonce()(uint256)" \
  --rpc-url http://localhost:8545
```

0보다 큰 값이 나와야 합니다. 블록이 생성될 때마다 증가합니다.

**Check 4: 과거 VRF 결과 조회**

```bash
# nonce 0의 결과 조회
cast call 0x42000000000000000000000000000000000000f0 \
  "getResult(uint256)(bytes32,bytes)" \
  0 \
  --rpc-url http://localhost:8545
```

**Check 5: getRandomness() 호출 (트랜잭션 필요)**

```bash
# 테스트 계정으로 getRandomness() 호출
cast send 0x42000000000000000000000000000000000000f0 \
  "getRandomness()(uint256)" \
  --rpc-url http://localhost:8545 \
  --private-key <TEST_PRIVATE_KEY>
```

**Check 6: ECVRF Verify Precompile 직접 호출**

```bash
# getResult로 beta, pi를 가져온 후 verify precompile 호출
# input: pk(33) + seed(32) + beta(32) + pi(81) = 178 bytes
cast call 0x0000000000000000000000000000000000000101 \
  <178_bytes_hex> \
  --rpc-url http://localhost:8545
```

출력이 `0x01`이면 검증 성공.

---

## 3. Demo Script

데모용 CoinFlip 컨트랙트를 배포하고 호출하는 스크립트입니다.

### 3.1 CoinFlip 컨트랙트 배포

```solidity
// CoinFlip.sol
pragma solidity ^0.8.0;

interface IEnshrainedVRF {
    function getRandomness() external returns (uint256);
}

contract CoinFlip {
    IEnshrainedVRF constant VRF = IEnshrainedVRF(0x42000000000000000000000000000000000000f0);
    
    event FlipResult(address indexed player, bool heads, uint256 randomness);
    
    function flip() external returns (bool heads) {
        uint256 randomness = VRF.getRandomness();
        heads = (randomness % 2 == 0);
        emit FlipResult(msg.sender, heads, randomness);
    }
}
```

### 3.2 배포 & 호출

```bash
# 배포
forge create CoinFlip \
  --rpc-url http://localhost:8545 \
  --private-key <TEST_PRIVATE_KEY>

# 결과에서 Deployed to: <COINFLIP_ADDR> 확인

# Flip 호출
cast send <COINFLIP_ADDR> "flip()(bool)" \
  --rpc-url http://localhost:8545 \
  --private-key <TEST_PRIVATE_KEY>

# 이벤트 로그 확인
cast logs --from-block latest \
  --address <COINFLIP_ADDR> \
  --rpc-url http://localhost:8545
```

### 3.3 Demo Flow 요약

```
1. devnet 시작
2. cast code 0x42...f0  → 바이트코드 존재 확인
3. cast call commitNonce()  → sequencer가 VRF 커밋 중 확인
4. forge create CoinFlip  → 데모 컨트랙트 배포
5. cast send flip()  → 동전 던지기 실행
6. cast logs  → FlipResult 이벤트에서 randomness 값 확인
7. cast call getResult(0)  → 과거 VRF proof 조회
8. verify precompile로 proof 검증  → 0x01 반환 확인
```

---

## 4. Troubleshooting

### "NoRandomnessAvailable" 에러

sequencer가 VRF를 커밋하지 않고 있습니다.
- `commitNonce()`가 0인지 확인
- sequencer에 VRF private key가 설정되었는지 확인
- `EnshrainedVRFTime`이 현재 timestamp 이전인지 확인

### EnshrainedVRF에 코드가 없음

genesis에 배치되지 않았습니다.
- `just genesis` 재실행
- `L2Genesis.s.sol`에 `setEnshrainedVRF()` 호출이 있는지 확인
- `Predeploys.sol`에 `isSupportedPredeploy`에 `ENSHRINED_VRF` 포함 확인

### op-geth 빌드 실패

```bash
cd op-geth
go build ./cmd/geth 2>&1 | head -20
```

### Verify precompile 0x0101이 응답하지 않음

fork가 활성화되지 않았습니다.
- chain config에 `"enshrainedVRFTime": 0` 확인
- `IsOptimismEnshrainedVRF`가 Rules에 있는지 확인

---

## 5. Test Matrix

| Layer | Test | Command | Expected |
|-------|------|---------|----------|
| Crypto | ECVRF round-trip | `go test ./crypto/ecvrf/ -v` | 22 PASS |
| Crypto | Fuzz | `go test ./crypto/ecvrf/ -fuzz=FuzzProveVerify -fuzztime=30s` | 0 crashes |
| EVM | Precompile | `go test ./core/vm/ -v` | 9 PASS |
| L2 | EnshrainedVRF | `cd contracts && forge test --match-contract EnshrainedVRFTest` | 30 PASS |
| L1 | VRFVerifier | `cd contracts && forge test --match-contract VRFVerifierTest` | 20 PASS |
| Build | op-geth binary | `cd op-geth && go build ./cmd/geth` | exit 0 |
| Build | op-node binary | `cd optimism && go build ./op-node/cmd` | exit 0 |
| E2E | Contract exists | `cast code 0x42...f0` | non-empty |
| E2E | VRF committing | `cast call commitNonce()` | > 0 |
| E2E | CoinFlip demo | `cast send flip()` | FlipResult event |
