import { browser } from '$app/environment';

const LS_KEY = 'tokamak:lang';

export type Lang = 'ko' | 'en';

const DICT: Record<Lang, Record<string, string>> = {
  ko: {
    'common.connect': 'connect',
    'common.connecting': 'connecting…',
    'common.retry': 'retry',
    'common.noWallet': 'no wallet',
    'common.footer':
      '로컬 데브넷에서 실행: <code>./scripts/arcade.sh</code> · MetaMask를 <code>localhost:8545</code>에 연결 · <a href="https://tokamak.network" target="_blank" rel="noopener">Backed by Tokamak Network</a>',
    'common.vrf.waking': 'waking up…',
    'common.vrf.offline': 'RPC offline',
    'common.back.landing': '← 랜딩으로',
    'common.back.games': '← 게임 목록으로',
    'common.raw': '최근 VRF randomness (raw)',
    'common.playnow': 'play now',
    'common.backedBy': 'Backed by Tokamak Network',

    'landing.title': 'Tokamak Arcade · play fair, play cute',
    'landing.eyebrow': 'On-chain mini-arcade · L2 native',
    'landing.featuresKicker': '작동 방식',
    'landing.lineupKicker': '오늘의 라인업',
    'landing.finalKicker': 'Ready to play',
    'landing.h1':
      '공정한 <span class="kw">미니게임</span>,<br>내장된 <span class="kw">난수</span>,<br>온체인 <span class="kw">아케이드</span>.',
    'landing.lede':
      'L2 컨트랙트가 <code>VRF.getRandomness()</code>를 한 번 호출하면 끝. 오라클도, 콜백도, 수상한 서버도 없이 — 단일 트랜잭션 안에서 결과가 확정됩니다.',
    'landing.cta.enter': 'Get Started',
    'landing.cta.how': '어떻게 작동하나요?',
    'landing.f1.t': 'L2에 박힌 난수',
    'landing.f1.b':
      'VRF는 프리디플로이 컨트랙트 주소로 네이티브하게 살아 있어요. 외부 oracle도, off-chain callback도 없이 opcode처럼 호출됩니다.',
    'landing.f2.t': '한 트랜잭션, 한 결과',
    'landing.f2.b':
      '주사위를 굴린다 → 즉시 결과. 콜백 대기나 request/fulfill 왕복 없이 플레이 트랜잭션 안에서 결과가 확정됩니다.',
    'landing.f3.t': '누구나 검증 가능',
    'landing.f3.b':
      '각 난수는 시퀀서가 사전 커밋한 뒤 공개되는 방식이라, 누구든 트랜잭션 해시만 있으면 공정성을 재연산할 수 있어요.',
    'landing.preview.t': '오늘의 라인업',
    'landing.preview.n': '6개의 미니게임이 열려 있어요',
    'landing.final.t': '준비됐다면 이 버튼 하나로.',
    'landing.final.b':
      '지갑을 데브넷에 연결하고 아케이드에 들어와 주세요. 테스트 ETH는 <code>scripts/arcade.sh</code> 실행 시 이미 프리펀드돼 있어요.',
    'landing.featured.t': 'Neverness to Everness',
    'landing.seeAll': 'See all',
    'landing.upcoming': 'Upcoming Games',

    'hub.title': 'Games · Tokamak Arcade',
    'hub.eyebrow': 'Pick your game',
    'hub.h1': '어떤 걸로 한번 놀아볼까요?',
    'hub.lede':
      '모든 게임은 L2 컨트랙트가 <code>VRF.getRandomness()</code>를 직접 호출해 단일 트랜잭션에서 결과가 정해집니다. 오라클 · 콜백 · 중앙 서버 없음.',
    'hub.allGames': '모든 게임',

    'games.janken.desc': '가위바위보 + 룰렛 + LP 풀. VRF 1콜 + AA 세션키로 서명 없는 플레이.',

    'janken.title': 'Jankenman · Tokamak Arcade',
    'janken.lead':
      '가위바위보 + 룰렛. 장기 기대값: 플레이어 <b>-7%</b> / LP <b>+7%</b>. 단일 VRF 호출로 상대 손 + 배율이 결정됩니다.',
    'janken.ready': '✊ ✋ ✌️ 손을 고르고 베팅하세요',
    'janken.signing': '지갑 서명 중…',
    'janken.waiting': '블록 기다리는 중…',
    'janken.you': 'You',
    'janken.house': 'House (VRF)',
    'janken.rock': '바위',
    'janken.paper': '보',
    'janken.scissors': '가위',
    'janken.betAmount': '베팅 금액 (ETH)',
    'janken.playBtn': '플레이',
    'janken.pool': '🏦 유동성 풀',
    'janken.poolAssets': '풀 (ETH)',
    'janken.totalShares': '총 LP 지분',
    'janken.myShares': '내 지분',
    'janken.myClaim': '내 청구권 (ETH)',
    'janken.lpDeposit': 'LP 예치',
    'janken.lpWithdraw': '전액 인출',
    'janken.defiNote':
      '<b>LP 수익 구조:</b> 플레이어 장기 EV -7% → 풀은 수학적으로 +7% 기대 수익. 단기 변동성은 20× 당첨으로 커질 수 있어, 단일 라운드 최대 payout은 풀의 10%로 제한.',
    'janken.defiShort':
      '<b>구조:</b> 베팅 → 컨트랙트 → LP 풀. Lose는 풀에 쌓이고, Win은 풀에서 배율만큼 지급. 단일 VRF 호출로 결정.',

    'janken.kpi.tvl': 'TVL (풀)',
    'janken.kpi.shares': '총 지분',
    'janken.kpi.houseEdge': '하우스 엣지',
    'janken.kpi.sharePrice': '지분 가격',
    'janken.tab.play': 'Play',
    'janken.tab.liquidity': 'Liquidity',
    'janken.board': '플레이 보드',
    'janken.slip': '베팅 슬립',
    'janken.slip.tag': '네이티브 ETH',
    'janken.slip.payout': '승리 시 payout',
    'janken.slip.odds': '확률',
    'janken.slip.ev': '기대 손익 (7% 하우스 엣지)',
    'janken.dist': '승리 시 배율 분포',
    'janken.yourPos': '내 포지션',
    'janken.poolShare': '풀 지분율',
    'janken.poolBreakdown': '풀 구성',
    'janken.manage': '유동성 관리',
    'janken.manage.tag': 'shares = amount × totalShares / TVL',
    'janken.depositLabel': 'ETH 예치 → LP 지분 발행',
    'janken.withdrawLabel': '지분 소각 → ETH 수령',
    'janken.max': 'max',
    'janken.recent': '최근 라운드',
    'janken.col.outcome': '결과',
    'janken.col.hand': '손',
    'janken.col.bet': '베팅',
    'janken.col.payout': 'payout',
    'janken.col.tx': 'tx',
    'janken.noRounds': '아직 라운드 없음 — 한 판 플레이하면 여기 표시됩니다.',

    'janken.kpi.vrf': 'Enshrined VRF · commit',
    'janken.playing': '세션키로 전송 중… (서명 없음)',
    'janken.err.lowCredits': '크레딧이 부족해요. 세션을 재충전해 주세요.',

    'janken.session.idle': '세션 없음',
    'janken.session.active': '세션 활성',
    'janken.session.expired': '세션 만료',
    'janken.session.ready': '✅ 세션 시작 — 이제 서명 없이 플레이할 수 있어요',
    'janken.session.credits': '인게임 크레딧',
    'janken.session.key': '세션키 주소',
    'janken.session.expires': '만료까지',
    'janken.session.gas': '세션키 가스',
    'janken.session.start': '세션 시작',
    'janken.session.topup': '크레딧 충전',
    'janken.session.end': '세션 종료 & 인출',
    'janken.session.topupPrompt': '추가 예치할 ETH 금액은?',
    'janken.session.endConfirm': '세션을 종료하고 남은 크레딧을 지갑으로 인출할까요?',

    'janken.modal.title': '아케이드 세션 시작',
    'janken.modal.sub':
      '한 번만 서명하면 ETH가 인게임 크레딧으로 들어가고, 브라우저에 보관된 세션키에 권한이 부여되며 가스까지 함께 충전됩니다. 이후엔 <b>지갑 팝업 없이</b> 모든 라운드가 바로 처리됩니다.',
    'janken.modal.deposit': '예치 (크레딧)',
    'janken.modal.gas': '세션키 가스',
    'janken.modal.gasHint':
      '약 50–200판의 playFor() tx를 커버합니다. 남은 가스는 세션 종료 시 환불되지 않으니 적게 시작하는 걸 권장.',
    'janken.modal.duration': '유효 기간',
    'janken.modal.key': '세션키 주소',
    'janken.modal.cancel': '취소',
    'janken.modal.confirm': '서명 후 시작',
    'janken.modal.signing': '지갑 서명 중…'
  },

  en: {
    'common.connect': 'connect',
    'common.connecting': 'connecting…',
    'common.retry': 'retry',
    'common.noWallet': 'no wallet',
    'common.footer':
      'Run the local devnet: <code>./scripts/arcade.sh</code> · point MetaMask at <code>localhost:8545</code> · <a href="https://tokamak.network" target="_blank" rel="noopener">Backed by Tokamak Network</a>',
    'common.vrf.waking': 'waking up…',
    'common.vrf.offline': 'RPC offline',
    'common.back.landing': '← back to landing',
    'common.back.games': '← back to games',
    'common.raw': 'latest VRF randomness (raw)',
    'common.playnow': 'play now',
    'common.backedBy': 'Backed by Tokamak Network',

    'landing.title': 'Tokamak Arcade · play fair, play cute',
    'landing.eyebrow': 'On-chain mini-arcade · L2 native',
    'landing.featuresKicker': 'How it works',
    'landing.lineupKicker': "Today's lineup",
    'landing.finalKicker': 'Ready to play',
    'landing.h1':
      'Fair <span class="kw">play</span>,<br>enshrined <span class="kw">randomness</span>,<br>on-chain <span class="kw">arcade</span>.',
    'landing.lede':
      "One call to <code>VRF.getRandomness()</code> and that's it. No oracle, no callback, no shady server — the outcome settles inside a single transaction.",
    'landing.cta.enter': 'Enter Arcade',
    'landing.cta.how': 'How does it work?',
    'landing.f1.t': 'Built into the L2',
    'landing.f1.b':
      'VRF lives natively at a pre-deployed contract address. No external oracle, no off-chain callback — call it like an opcode.',
    'landing.f2.t': 'One tx, one result',
    'landing.f2.b':
      'Roll the dice → result, instantly. No request/fulfill round-trip — the outcome settles inside the play transaction itself.',
    'landing.f3.t': 'Verifiable by anyone',
    'landing.f3.b':
      'Each randomness is pre-committed by the sequencer and revealed later, so anyone with the tx hash can recompute fairness.',
    'landing.preview.t': "Today's line-up",
    'landing.preview.n': '6 mini-games currently open',
    'landing.final.t': 'Ready? One button does it.',
    'landing.final.b':
      'Connect your wallet to the devnet and step in. Test ETH is pre-funded when you run <code>scripts/arcade.sh</code>.',
    'landing.featured.t': 'Featured games',
    'landing.seeAll': 'See all',
    'landing.upcoming': 'Upcoming Games',

    'hub.title': 'Games · Tokamak Arcade',
    'hub.eyebrow': 'Pick your game',
    'hub.h1': 'Which one today?',
    'hub.lede':
      'Every game calls <code>VRF.getRandomness()</code> directly from its L2 contract — the outcome settles in a single transaction. No oracle, no callback, no central server.',
    'hub.allGames': 'All games',

    'games.janken.desc':
      'Rock-paper-scissors + roulette + LP pool. One VRF call per round; AA session keys for zero-sig play.',

    'janken.title': 'Jankenman · Tokamak Arcade',
    'janken.lead':
      'Rock-paper-scissors + roulette. Long-run EV: player <b>-7%</b> / LP <b>+7%</b>. One VRF call decides both the house hand and the win multiplier.',
    'janken.ready': '✊ ✋ ✌️ pick a hand and place your bet',
    'janken.signing': 'signing in wallet…',
    'janken.waiting': 'waiting for block…',
    'janken.you': 'You',
    'janken.house': 'House (VRF)',
    'janken.rock': 'Rock',
    'janken.paper': 'Paper',
    'janken.scissors': 'Scissors',
    'janken.betAmount': 'bet amount (ETH)',
    'janken.playBtn': 'Play',
    'janken.pool': '🏦 Liquidity pool',
    'janken.poolAssets': 'pool (ETH)',
    'janken.totalShares': 'total shares',
    'janken.myShares': 'my shares',
    'janken.myClaim': 'my claim (ETH)',
    'janken.lpDeposit': 'Deposit LP',
    'janken.lpWithdraw': 'Withdraw all',
    'janken.defiNote':
      '<b>LP yield:</b> player long-run EV of -7% ⇒ pool earns a mathematical +7% edge. Short-run variance is amplified by 20× wins, so max single-round payout is capped at 10% of the pool.',
    'janken.defiShort':
      '<b>Flow:</b> bet → contract → LP pool. Losses accrue into the pool; wins are paid out at the roulette multiplier. One VRF call decides both.',

    'janken.kpi.tvl': 'TVL (pool)',
    'janken.kpi.shares': 'total shares',
    'janken.kpi.houseEdge': 'house edge',
    'janken.kpi.sharePrice': 'share price',
    'janken.tab.play': 'Play',
    'janken.tab.liquidity': 'Liquidity',
    'janken.board': 'Play board',
    'janken.slip': 'Bet slip',
    'janken.slip.tag': 'native ETH',
    'janken.slip.payout': 'if you win',
    'janken.slip.odds': 'odds',
    'janken.slip.ev': 'expected P/L (7% house edge)',
    'janken.dist': 'Multiplier distribution (on win)',
    'janken.yourPos': 'Your position',
    'janken.poolShare': 'pool share',
    'janken.poolBreakdown': 'pool breakdown',
    'janken.manage': 'Manage liquidity',
    'janken.manage.tag': 'shares = amount × totalShares / TVL',
    'janken.depositLabel': 'Deposit ETH → mint LP shares',
    'janken.withdrawLabel': 'Burn shares → receive ETH',
    'janken.max': 'max',
    'janken.recent': 'Recent rounds',
    'janken.col.outcome': 'outcome',
    'janken.col.hand': 'hand',
    'janken.col.bet': 'bet',
    'janken.col.payout': 'payout',
    'janken.col.tx': 'tx',
    'janken.noRounds': 'No rounds yet — play one to see it here.',

    'janken.kpi.vrf': 'Enshrined VRF · commit',
    'janken.playing': 'session key is broadcasting… (no signature needed)',
    'janken.err.lowCredits': 'Not enough credits. Top up to keep playing.',

    'janken.session.idle': 'no session',
    'janken.session.active': 'session active',
    'janken.session.expired': 'session expired',
    'janken.session.ready': '✅ session started — zero-sig play is on',
    'janken.session.credits': 'in-game credits',
    'janken.session.key': 'session key',
    'janken.session.expires': 'expires in',
    'janken.session.gas': 'key gas',
    'janken.session.start': 'Start session',
    'janken.session.topup': 'Top up credits',
    'janken.session.end': 'End & withdraw',
    'janken.session.topupPrompt': 'How much ETH to add?',
    'janken.session.endConfirm': 'Revoke the session key and withdraw remaining credits?',

    'janken.modal.title': 'Start an arcade session',
    'janken.modal.sub':
      "Sign once to deposit ETH as in-game credits, authorise a browser-held session key, and fund it with a tiny amount of gas. After this tx, every round settles <b>with zero wallet popups</b> until the session expires or you withdraw.",
    'janken.modal.deposit': 'Deposit (credits)',
    'janken.modal.gas': 'Session gas fund',
    'janken.modal.gasHint':
      "Covers roughly 50–200 playFor() txs. Start small — surplus gas isn't refunded when the session ends.",
    'janken.modal.duration': 'Valid for',
    'janken.modal.key': 'Session key address',
    'janken.modal.cancel': 'Cancel',
    'janken.modal.confirm': 'Sign & start',
    'janken.modal.signing': 'signing in wallet…'
  }
};

function loadInitial(): Lang {
  if (!browser) return 'en';
  try {
    const v = localStorage.getItem(LS_KEY);
    if (v === 'ko' || v === 'en') return v;
  } catch {}
  return 'en';
}

function createI18n() {
  let current = $state<Lang>(loadInitial());

  if (browser) document.documentElement.lang = current;

  function set(lang: Lang) {
    if (lang !== 'ko' && lang !== 'en') return;
    if (lang === current) return;
    current = lang;
    if (browser) {
      try {
        localStorage.setItem(LS_KEY, lang);
      } catch {}
      document.documentElement.lang = lang;
    }
  }

  function toggle() {
    set(current === 'ko' ? 'en' : 'ko');
  }

  function t(key: string): string {
    return DICT[current][key] ?? DICT.ko[key] ?? key;
  }

  return {
    get lang() {
      return current;
    },
    set,
    toggle,
    t
  };
}

export const i18n = createI18n();
