# pongy.bet

온체인 정산 · USDC 보상 · VRF 검증 스테이블코인 짱깸뽀 아케이드.

## 실행

ES 모듈을 사용하므로 정적 서버가 필요합니다.

```bash
python3 -m http.server 8000
# 또는
npx serve .
```

→ http://localhost:8000 에서 게임 열기.

## 게임 루프

1. 지갑에서 $1 USDC를 베팅 (▶ bet $1 USDC)
2. "짱-깸-뽀!" 대전 → 바위·가위·보 중 하나 선택
3. 승리 시 룰렛이 회전하여 배수 결정 (1× · 2× · 4× · 7× · 20×)
4. USDC 수령 → 언제든 지갑으로 출금 가능

## 룰렛 분포

| 배수 | 확률 | 의미 |
|------|------|------|
| 1× | 50% | 꽝 (본전) |
| 2× | 25% | 두배 |
| 4× | 15% | 네배 |
| 7× | 8%  | 별 |
| 20× | 2% | 대박 (FEVER 연출) |

기대 배당 2.56× · 하우스 엣지 2.5%.

## 구조

```
index.html          — 게임 (진입점)
shared/
  engine.js         — GameEngine 인터페이스 + LocalEngine
  runtime.js        — 상태머신 + 렌더러 + 테마 훅
  audio.js          — 8-bit 칩튠 SFX + BGM
  retro.css         — 공용 디자인 토큰
```

모든 난수·잔액·정산 로직이 `GameEngine` 뒤에 추상화되어 있으므로, 로컬
엔진을 VRF + USDC 컨트랙트 엔진으로 교체해도 UI는 변경 없이 작동합니다.

## Enshrined VRF 프로토콜 연동

현재 게임은 `createLocalEngine()`(Math.random)으로 돌아갑니다. 이걸 L2
체인과 연결하려면 엔진 한 줄만 교체하면 됩니다.

### 1. 컨트랙트 배포

[`contracts/src/examples/PongyBet.sol`](../contracts/src/examples/PongyBet.sol) — 1 USDC
베팅 · 가위바위보 + 룰렛을 **`VRF.getRandomness()`** 한 번으로 정산.

```bash
cd contracts
# USDC 주소 입력
forge create src/examples/PongyBet.sol:PongyBet \
  --rpc-url $L2_RPC --private-key $PK \
  --constructor-args $USDC_ADDRESS
```

컨트랙트 요점:
- `deposit(amount)` — USDC approve 후 예치
- `play(hand)` — 1 USDC 차감 → VRF 호출 → 가위바위보 판정 → 승 시 룰렛 → 단일 tx 정산
- `withdraw()` — 메달을 USDC로 출금
- 1 블록에 1 VRF 커밋, 여러 콜은 `keccak256(beta, callCounter)`로 per-call 유니크

### 2. 프론트엔드 엔진 교체

`shared/engine-onchain.js`가 `GameEngine` 인터페이스 그대로 구현합니다. `index.html`에서:

```js
// 기존
import { createLocalEngine } from './shared/engine.js?v=2';
const engine = createLocalEngine();

// 교체
import { createOnChainEngine } from './shared/engine-onchain.js?v=2';
const engine = await createOnChainEngine({
  chainRpc:    'https://l2.enshrined-vrf.local',      // L2 RPC
  gameAddress: '0xYourPongyBetDeploy',                // 1번에서 배포한 주소
  usdcAddress: '0xUSDCOnL2',                          // L2의 USDC
  wallet:      window.ethereum,                       // MetaMask 등 EIP-1193
});
```

runtime · UI · 룰렛 연출 · 사운드는 전혀 건드릴 필요 없습니다 — `createGame({ ... })`가
엔진을 인자로 받지는 않으므로, `runtime.js`의 `createLocalEngine` 직접 import를
엔진 주입식으로 살짝 바꿔주는 것만 필요합니다 (`createGame({ engine })`).

### 3. 주요 매핑

| 프론트 `PlayResult` 필드 | 컨트랙트 `Played` 이벤트 |
|--------------------------|--------------------------|
| `playerHand/machineHand` | `playerHand/machineHand` (0=rock·1=scissors·2=paper) |
| `outcome`                | `outcome` (0=lose·1=draw·2=win) |
| `multiplier`             | `multiplier` (0 또는 1/2/4/7/20) |
| `payout`                 | `payout` (USDC 최소단위 → BET로 나눠 정수화) |
| `rngSeed`                | `randomness` (VRF beta — 검증 가능) |
| `roundId`                | `tx hash` (유니크) |

### 4. 검증 가능성

매 라운드마다 `randomness`가 이벤트에 기록됩니다. 누구나:
1. `VRF.getResult(nonce)` 로 `(seed, beta, pi)` 조회
2. `VRFVerifier.verify(pk, seed, pi, beta)` 로 ECVRF 증명 확인
3. `randomness == uint256(keccak256(beta, callCounter))` 검산

→ 시퀀서가 결과를 조작할 수 없음(fault-provable).

## 라이선스

자산은 자체 제작 또는 합성 (WebAudio). 원본 Sunwise "Janken-man" 자산은
사용되지 않습니다.
