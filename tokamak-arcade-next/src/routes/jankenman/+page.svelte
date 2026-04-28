<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { decodeEventLog, formatEther, parseEther, type Hash } from 'viem';
  import { i18n } from '$lib/i18n.svelte';
  import { wallet, pub, shortAddr } from '$lib/wallet.svelte';
  import { CONFIG } from '$lib/config';
  import Topbar from '$lib/components/Topbar.svelte';
  import { jankenMascot } from '$lib/mascots';
  import {
    JANKENMAN_ABI as ABI,
    VRF_ABI,
    TX_FEES,
    HANDS,
    HAND_NAMES,
    MULTS,
    WHEEL_SEGMENTS
  } from '$lib/jankenman/abi';
  import { getSessionKey } from '$lib/jankenman/session.svelte';

  // ─── State ────────────────────────────────────────────────────────
  let selectedHand = $state<number | null>(null);
  let betEth = $state('0.01');

  type RoundResult = {
    outcome: number;
    mult: number;
    bet: bigint;
    payout: bigint;
    pHand: number;
    hHand: number;
  };
  type HistoryRow = { result: RoundResult; hash: Hash };

  let lastResult = $state<RoundResult | null>(null);
  let history = $state<HistoryRow[]>([]);
  let randHex = $state<string>('—');

  // Display animation state
  let displayEmoji = $state<string>(HANDS[0]);
  let displayCycling = $state(true);
  let displayResultClass = $state<'' | 'result-win' | 'result-lose' | 'result-draw'>('');
  let cycleTimer: ReturnType<typeof setInterval> | null = null;

  let wheelRotation = $state(0);
  let wheelTransitionMs = $state(3800);

  // Status LED
  let statusKind = $state<'' | 'win' | 'lose' | 'draw'>('');
  let statusText = $state<string>('');
  let statusHtml = $state<boolean>(false);

  // Tab
  let activeTab = $state<'play' | 'liquidity'>('play');

  // KPIs / pool
  let kpiTvl = $state('—');
  let kpiPrice = $state('1.0000');
  let kpiVrf = $state('—');
  let posShares = $state('—');
  let posClaimEth = $state('—');
  let posPct = $state('—');
  let poolTotal = $state('—');
  let poolYou = $state('0');
  let poolOthers = $state('0');
  let poolBarMine = $state(0);
  let depositPreview = $state('—');
  let withdrawPreview = $state('—');

  // LP form
  let lpAmount = $state('0.5');
  let lpWithdrawShares = $state('0');

  // Session strip
  let sessionActive = $state(false);
  let sessionValidUntil = $state(0n);
  let sessionCredits = $state(0n);
  let sessionGas = $state(0n);
  let sessionBadge = $derived.by(() => {
    if (sessionActive) return { text: i18n.t('janken.session.active'), cls: 'active' };
    if (sessionValidUntil > 0n) return { text: i18n.t('janken.session.expired'), cls: 'expired' };
    return { text: i18n.t('janken.session.idle'), cls: 'idle' };
  });
  let sessionRemaining = $state(0);

  // Modal
  let modalOpen = $state(false);
  let modalDeposit = $state('0.5');
  let modalGas = $state('0.02');
  let modalHours = $state('2');
  let modalSigning = $state(false);

  let busy = $state(false);
  let healthcheckMsg = $state<string | null>(null);

  // Refs / timers
  let pollPool: ReturnType<typeof setInterval> | null = null;
  let pollSession: ReturnType<typeof setInterval> | null = null;
  let pollVrf: ReturnType<typeof setInterval> | null = null;

  // Lazily resolved session key (browser-only)
  let session = $state<ReturnType<typeof getSessionKey> | null>(null);

  // ─── Display helpers ──────────────────────────────────────────────
  function startCycling(intervalMs = 140) {
    stopCycling();
    displayCycling = true;
    let i = 0;
    cycleTimer = setInterval(() => {
      i = (i + 1) % 3;
      displayEmoji = HANDS[i];
    }, intervalMs);
  }
  function stopCycling() {
    if (cycleTimer) {
      clearInterval(cycleTimer);
      cycleTimer = null;
    }
    displayCycling = false;
  }
  function lockDisplay(emoji: string, kind: '' | 'win' | 'lose' | 'draw') {
    stopCycling();
    displayEmoji = emoji;
    displayResultClass = kind ? (`result-${kind}` as const) : '';
  }

  function setStatus(kind: '' | 'win' | 'lose' | 'draw', text: string, html = false) {
    statusKind = kind;
    statusText = text;
    statusHtml = html;
  }

  // ─── Wheel animation ──────────────────────────────────────────────
  async function spinWheel(winningMult: number) {
    const matches = WHEEL_SEGMENTS.map((s, i) => (s.m === winningMult ? i : -1)).filter(
      (i) => i >= 0
    );
    const segIdx = matches[Math.floor(Math.random() * matches.length)];
    const finalAngle = -(segIdx * 36 + 18);
    const base = Math.ceil(wheelRotation / 360) * 360;
    const target = base + 360 * 5 + finalAngle;
    wheelTransitionMs = 3600;
    wheelRotation = target;
    await new Promise((r) => setTimeout(r, 3700));
  }

  // ─── Healthcheck on mount ─────────────────────────────────────────
  async function healthcheck() {
    const blank = '0x0000000000000000000000000000000000000000';
    if (!CONFIG.jankenman || CONFIG.jankenman === blank) {
      return { ok: false, reason: 'CONFIG.jankenman is empty — set VITE_JANKENMAN_ADDRESS in .env' };
    }
    let chainId: number;
    try {
      chainId = await pub.getChainId();
    } catch {
      return { ok: false, reason: `RPC unreachable at ${CONFIG.rpc}` };
    }
    if (chainId !== CONFIG.chainId) {
      return {
        ok: false,
        reason: `RPC chainId=${chainId}, expected ${CONFIG.chainId}.`
      };
    }
    try {
      const code = await pub.getBytecode({ address: CONFIG.jankenman });
      if (!code || code === '0x') {
        return { ok: false, reason: `No contract at ${CONFIG.jankenman}.` };
      }
    } catch {
      return { ok: false, reason: `Could not fetch code at ${CONFIG.jankenman}.` };
    }
    return { ok: true as const };
  }

  // ─── Reads ────────────────────────────────────────────────────────
  async function refreshPool() {
    try {
      const me = wallet.account;
      const [pool, shares, myShares] = await Promise.all([
        pub.readContract({ address: CONFIG.jankenman, abi: ABI, functionName: 'lpAssets' }),
        pub.readContract({ address: CONFIG.jankenman, abi: ABI, functionName: 'totalShares' }),
        me
          ? pub.readContract({
              address: CONFIG.jankenman,
              abi: ABI,
              functionName: 'sharesOf',
              args: [me]
            })
          : Promise.resolve(0n)
      ]);
      const poolEth = Number(formatEther(pool));
      const myClaim = shares === 0n || myShares === 0n ? 0n : (myShares * pool) / shares;
      const myClaimEth = Number(formatEther(myClaim));
      const myPct = poolEth === 0 ? 0 : (myClaimEth / poolEth) * 100;

      kpiTvl = poolEth.toFixed(4);
      kpiPrice = (shares === 0n ? 1 : poolEth / Number(shares)).toFixed(6);

      posShares = myShares.toString();
      posClaimEth = myClaimEth.toFixed(6);
      posPct = myPct.toFixed(2) + '%';

      poolTotal = poolEth.toFixed(4);
      poolYou = myClaimEth.toFixed(4);
      poolOthers = Math.max(0, poolEth - myClaimEth).toFixed(4);
      poolBarMine = Math.min(100, myPct);

      // LP previews
      const amt = Number(lpAmount || 0);
      let depPrev = '—';
      if (amt > 0) {
        if (shares === 0n || pool === 0n)
          depPrev = `≈ ${Math.floor(amt * 1e18)} shares (first deposit)`;
        else
          depPrev = `≈ ${Math.floor((amt * Number(shares)) / Number(formatEther(pool)))} shares`;
      }
      depositPreview = depPrev;

      let wShares = 0n;
      try {
        wShares = BigInt(lpWithdrawShares || '0');
      } catch {}
      let wdPrev = '—';
      if (wShares > 0n && shares > 0n) {
        const amtWei = (wShares * pool) / shares;
        wdPrev = `≈ ${Number(formatEther(amtWei)).toFixed(6)} ETH`;
      }
      withdrawPreview = wdPrev;
    } catch (err) {
      console.error('[pool]', err);
    }
  }

  async function refreshSession() {
    if (!session) return;
    const me = wallet.account;
    if (!me) {
      sessionActive = false;
      sessionValidUntil = 0n;
      sessionCredits = 0n;
      sessionGas = 0n;
      sessionRemaining = 0;
      return;
    }
    try {
      const [validUntil, creditsBig, gasBalance] = await Promise.all([
        pub.readContract({
          address: CONFIG.jankenman,
          abi: ABI,
          functionName: 'sessionKey',
          args: [me, session.account.address]
        }),
        pub.readContract({
          address: CONFIG.jankenman,
          abi: ABI,
          functionName: 'credits',
          args: [me]
        }),
        pub.getBalance({ address: session.account.address })
      ]);
      const nowSec = BigInt(Math.floor(Date.now() / 1000));
      const isActive = validUntil > nowSec;
      sessionActive = isActive;
      sessionValidUntil = validUntil;
      sessionCredits = creditsBig;
      sessionGas = gasBalance;
      sessionRemaining = isActive ? Number(validUntil - nowSec) : 0;
    } catch (err) {
      console.warn('[session refresh]', err);
    }
  }

  async function refreshVrf() {
    try {
      const n = await pub.readContract({
        address: CONFIG.vrfAddress,
        abi: VRF_ABI,
        functionName: 'commitNonce'
      });
      kpiVrf = n.toString();
    } catch {}
  }

  // ─── Play (zero-popup, session key) ───────────────────────────────
  async function play() {
    if (selectedHand === null || !session) return;
    let betWei: bigint;
    try {
      betWei = parseEther(String(betEth || '0'));
    } catch {
      alert('Invalid bet amount');
      return;
    }
    if (betWei === 0n) return;

    const me = wallet.account;
    if (!me) {
      setStatus('lose', 'CONNECT WALLET FIRST (top right)');
      return;
    }

    let liveValidUntil = 0n,
      liveCredits = 0n,
      liveGas = 0n;
    try {
      [liveValidUntil, liveCredits, liveGas] = await Promise.all([
        pub.readContract({
          address: CONFIG.jankenman,
          abi: ABI,
          functionName: 'sessionKey',
          args: [me, session.account.address]
        }),
        pub.readContract({
          address: CONFIG.jankenman,
          abi: ABI,
          functionName: 'credits',
          args: [me]
        }),
        pub.getBalance({ address: session.account.address })
      ]);
    } catch (err) {
      console.error('[preflight]', err);
      setStatus('lose', 'RPC unreachable — is scripts/arcade.sh running?');
      return;
    }
    const nowSec = BigInt(Math.floor(Date.now() / 1000));
    if (liveValidUntil <= nowSec) {
      setStatus('lose', 'NO ACTIVE SESSION — use "Start session" above');
      return;
    }
    if (liveCredits < betWei) {
      setStatus(
        'lose',
        `LOW CREDITS · have ${formatEther(liveCredits)} · need ${formatEther(betWei)}`
      );
      return;
    }
    if (liveGas === 0n) {
      setStatus('lose', 'SESSION KEY OUT OF GAS · end session & restart');
      return;
    }

    busy = true;
    lockDisplay(HANDS[0], '');
    startCycling(80);
    setStatus('', i18n.t('janken.playing'));

    try {
      await pub.simulateContract({
        account: session.account.address,
        address: CONFIG.jankenman,
        abi: ABI,
        functionName: 'playFor',
        args: [me, selectedHand, betWei]
      });

      const hash = await session.client.writeContract({
        account: session.account,
        chain: null,
        address: CONFIG.jankenman,
        abi: ABI,
        functionName: 'playFor',
        args: [me, selectedHand, betWei],
        ...TX_FEES
      });
      setStatus('', i18n.t('janken.waiting'));
      const receipt = await pub.waitForTransactionReceipt({ hash });

      let evArgs: any;
      for (const log of receipt.logs) {
        if (log.address.toLowerCase() !== CONFIG.jankenman.toLowerCase()) continue;
        try {
          const dec = decodeEventLog({ abi: ABI, data: log.data, topics: log.topics });
          if (dec.eventName === 'Played') {
            evArgs = dec.args as any;
            break;
          }
        } catch {}
      }
      if (!evArgs) throw new Error('no Played event');

      const result: RoundResult = {
        outcome: Number(evArgs.outcome),
        mult: Number(evArgs.multiplier),
        bet: evArgs.bet,
        payout: evArgs.payout,
        pHand: Number(evArgs.playerHand),
        hHand: Number(evArgs.houseHand)
      };
      lastResult = result;
      randHex = '0x' + (evArgs.randomness as bigint).toString(16).padStart(64, '0');

      if (result.outcome === 2) {
        setStatus('win', `🎲 SPINNING FOR ${result.mult}× …`);
        await spinWheel(result.mult);
      }
      paintResult();
      history = [{ result, hash }, ...history].slice(0, 8);
      await refreshPool();
      await refreshSession();
    } catch (err: any) {
      console.error('[play]', err);
      stopCycling();
      const msg =
        err?.cause?.shortMessage ||
        err?.shortMessage ||
        err?.details ||
        err?.message ||
        'failed';
      setStatus('lose', String(msg).slice(0, 160));
    } finally {
      busy = false;
    }
  }

  function paintResult() {
    if (!lastResult) {
      startCycling();
      setStatus('', i18n.t('janken.ready'));
      return;
    }
    const { outcome, mult, bet, payout, hHand } = lastResult;
    const kind = outcome === 2 ? 'win' : outcome === 1 ? 'draw' : 'lose';
    lockDisplay(HANDS[hHand], kind);

    if (outcome === 1) {
      setStatus('draw', `🤝 DRAW · <b>${formatEther(bet)} ETH</b> REFUNDED`, true);
    } else if (outcome === 0) {
      setStatus('lose', `💧 LOSS · <b>−${formatEther(bet)} ETH</b> → POOL`, true);
    } else {
      setStatus('win', `🎉 WIN <b>${mult}×</b> · <b>+${formatEther(payout)} ETH</b>`, true);
    }
  }

  // ─── Session lifecycle ────────────────────────────────────────────
  async function openSessionModal() {
    if (!wallet.account) {
      try {
        await wallet.connect();
      } catch {
        return;
      }
    }
    modalOpen = true;
  }

  async function startSession() {
    if (!session) return;
    if (!wallet.account) {
      try {
        await wallet.connect();
      } catch {
        return;
      }
    }
    let depositWei = 0n,
      gasFundWei = 0n,
      hours = 1;
    try {
      depositWei = parseEther(String(modalDeposit || '0'));
      gasFundWei = parseEther(String(modalGas || '0'));
      hours = Math.max(1, Math.min(24, Number(modalHours || 1)));
    } catch {
      alert('Invalid amounts');
      return;
    }
    if (depositWei + gasFundWei === 0n) return;
    const MIN_GAS = parseEther('0.005');
    if (gasFundWei < MIN_GAS) {
      alert('Session gas fund should be ≥ 0.005 ETH — bumping to minimum.');
      gasFundWei = MIN_GAS;
    }

    const validUntil = BigInt(Math.floor(Date.now() / 1000) + hours * 3600);
    const total = depositWei + gasFundWei;

    modalSigning = true;
    try {
      const hash = await wallet.wallet!.writeContract({
        account: wallet.account!,
        chain: null,
        address: CONFIG.jankenman,
        abi: ABI,
        functionName: 'startSession',
        args: [session.account.address, validUntil, gasFundWei],
        value: total
      });
      await pub.waitForTransactionReceipt({ hash });
      modalOpen = false;
      await refreshSession();
      await refreshPool();
      setStatus('', i18n.t('janken.session.ready'));
    } catch (err: any) {
      console.error('[startSession]', err);
      alert(err?.shortMessage || err?.message || 'failed');
    } finally {
      modalSigning = false;
    }
  }

  async function topUp() {
    const raw = prompt(i18n.t('janken.session.topupPrompt'), '0.1');
    if (!raw) return;
    let amt = 0n;
    try {
      amt = parseEther(String(raw));
    } catch {
      return;
    }
    if (amt === 0n) return;
    if (!wallet.account) {
      try {
        await wallet.connect();
      } catch {
        return;
      }
    }
    try {
      const hash = await wallet.wallet!.writeContract({
        account: wallet.account!,
        chain: null,
        address: CONFIG.jankenman,
        abi: ABI,
        functionName: 'deposit',
        value: amt
      });
      await pub.waitForTransactionReceipt({ hash });
      await refreshSession();
    } catch (err: any) {
      alert(err?.shortMessage || err?.message);
    }
  }

  async function endSession() {
    if (!session) return;
    if (!confirm(i18n.t('janken.session.endConfirm'))) return;
    if (!wallet.account) {
      try {
        await wallet.connect();
      } catch {
        return;
      }
    }
    const owner = wallet.account!;
    try {
      if (sessionActive) {
        const h1 = await wallet.wallet!.writeContract({
          account: owner,
          chain: null,
          address: CONFIG.jankenman,
          abi: ABI,
          functionName: 'revokeSession',
          args: [session.account.address]
        });
        await pub.waitForTransactionReceipt({ hash: h1 });
      }
      if (sessionCredits > 0n) {
        const h2 = await wallet.wallet!.writeContract({
          account: owner,
          chain: null,
          address: CONFIG.jankenman,
          abi: ABI,
          functionName: 'withdraw'
        });
        await pub.waitForTransactionReceipt({ hash: h2 });
      }
      const keyBal = await pub.getBalance({ address: session.account.address });
      const gasCost = TX_FEES.maxFeePerGas * 21_000n;
      if (keyBal > gasCost) {
        try {
          const h3 = await session.client.sendTransaction({
            account: session.account,
            chain: null,
            to: owner,
            value: keyBal - gasCost,
            gas: 21_000n,
            maxFeePerGas: TX_FEES.maxFeePerGas,
            maxPriorityFeePerGas: TX_FEES.maxPriorityFeePerGas
          });
          await pub.waitForTransactionReceipt({ hash: h3 });
        } catch (e) {
          console.warn('[end] sweep skipped', e);
        }
      }
      await refreshSession();
      await refreshPool();
    } catch (err: any) {
      console.error('[end]', err);
      alert(err?.shortMessage || err?.message);
    }
  }

  // ─── LP actions (owner-signed) ────────────────────────────────────
  async function lpDeposit() {
    let amountWei = 0n;
    try {
      amountWei = parseEther(String(lpAmount || '0'));
    } catch {
      alert('Invalid amount');
      return;
    }
    if (amountWei === 0n) return;
    if (!wallet.account) {
      try {
        await wallet.connect();
      } catch {
        return;
      }
    }
    try {
      const hash = await wallet.wallet!.writeContract({
        account: wallet.account!,
        chain: null,
        address: CONFIG.jankenman,
        abi: ABI,
        functionName: 'depositLP',
        value: amountWei
      });
      await pub.waitForTransactionReceipt({ hash });
      await refreshPool();
    } catch (err: any) {
      console.error(err);
      alert(err?.shortMessage || err?.message || 'failed');
    }
  }

  async function lpWithdraw() {
    let sharesBig = 0n;
    try {
      sharesBig = BigInt(lpWithdrawShares || '0');
    } catch {
      alert('Invalid shares');
      return;
    }
    if (sharesBig === 0n) return;
    if (!wallet.account) {
      try {
        await wallet.connect();
      } catch {
        return;
      }
    }
    try {
      const hash = await wallet.wallet!.writeContract({
        account: wallet.account!,
        chain: null,
        address: CONFIG.jankenman,
        abi: ABI,
        functionName: 'withdrawLP',
        args: [sharesBig]
      });
      await pub.waitForTransactionReceipt({ hash });
      await refreshPool();
    } catch (err: any) {
      console.error(err);
      alert(err?.shortMessage || err?.message || 'failed');
    }
  }

  async function lpMax() {
    if (!wallet.account) {
      try {
        await wallet.connect();
      } catch {
        return;
      }
    }
    const myShares = await pub.readContract({
      address: CONFIG.jankenman,
      abi: ABI,
      functionName: 'sharesOf',
      args: [wallet.account!]
    });
    lpWithdrawShares = myShares.toString();
    await refreshPool();
  }

  // ─── Derived ──────────────────────────────────────────────────────
  const betNum = $derived(Number(betEth || '0'));
  const evNum = $derived(-0.07 * betNum);
  const fmt = (x: number) => (x >= 100 ? x.toFixed(1) : x >= 10 ? x.toFixed(2) : x.toFixed(4));
  const playDisabled = $derived(busy || selectedHand === null);
  const sessionRemainingLabel = $derived.by(() => {
    if (!sessionActive) return '—';
    const s = sessionRemaining;
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
  });
  const sessionKeyAddr = $derived(session ? shortAddr(session.account.address) : '—');
  const sessionKeyFull = $derived(session ? session.account.address : '—');

  function setHand(i: number) {
    selectedHand = i;
  }
  function preset(v: string) {
    betEth = v;
  }

  // ─── Mount / cleanup ──────────────────────────────────────────────
  onMount(() => {
    session = getSessionKey();
    startCycling();
    paintResult();

    healthcheck().then((h) => {
      if (!h.ok) {
        healthcheckMsg = h.reason!;
        setStatus('lose', 'SETUP: ' + h.reason!.toUpperCase());
        stopCycling();
      }
    });

    refreshPool();
    refreshSession();
    refreshVrf();

    pollPool = setInterval(refreshPool, 4000);
    pollSession = setInterval(refreshSession, 2500);
    pollVrf = setInterval(refreshVrf, 1000);
  });

  onDestroy(() => {
    if (cycleTimer) clearInterval(cycleTimer);
    if (pollPool) clearInterval(pollPool);
    if (pollSession) clearInterval(pollSession);
    if (pollVrf) clearInterval(pollVrf);
  });

  // ─── Wheel labels (built once) ────────────────────────────────────
  const wheelLabels = WHEEL_SEGMENTS.map((seg, i) => ({
    angle: i * 36 + 18,
    m: seg.m
  }));
</script>

<svelte:head>
  <title>{i18n.t('janken.title')}</title>
</svelte:head>

<div id="topbar">
  <Topbar hubHref="/" brand={true} />
</div>

<div class="dfi-shell">
  <a class="tokamak-back" href="/">{i18n.t('common.back.landing')}</a>

  <div class="dfi-head">
    <div class="mascot">{@html jankenMascot({ size: 44 })}</div>
    <h2>Jankenman</h2>
    <span class="contract-pill">
      <b>contract</b>
      <span>
        {CONFIG.jankenman === '0x0000000000000000000000000000000000000000'
          ? 'not deployed'
          : `${CONFIG.jankenman.slice(0, 6)}…${CONFIG.jankenman.slice(-4)}`}
      </span>
    </span>
  </div>

  <!-- KPI strip -->
  <div class="kpi-strip">
    <div class="kpi">
      <span class="k">{i18n.t('janken.kpi.tvl')}</span>
      <span class="v">{kpiTvl}<span class="u">ETH</span></span>
    </div>
    <div class="kpi vrf">
      <span class="pulse-dot"></span>
      <span class="k">{i18n.t('janken.kpi.vrf')}</span>
      <span class="v">#{kpiVrf}</span>
    </div>
    <div class="kpi blue">
      <span class="k">{i18n.t('janken.kpi.houseEdge')}</span>
      <span class="v">7.00<span class="u">%</span></span>
    </div>
    <div class="kpi">
      <span class="k">{i18n.t('janken.kpi.sharePrice')}</span>
      <span class="v">{kpiPrice}<span class="u">Ξ / share</span></span>
    </div>
  </div>

  <!-- Session strip -->
  <div class="session-strip">
    <span class="status-badge {sessionBadge.cls}">{sessionBadge.text}</span>
    <div class="session-chips">
      <div class="session-chip hl">
        <span class="k">{i18n.t('janken.session.credits')}</span>
        <span class="v">{Number(formatEther(sessionCredits)).toFixed(4)} ETH</span>
      </div>
      <div class="session-chip">
        <span class="k">{i18n.t('janken.session.key')}</span>
        <span class="v" title={sessionKeyFull}>{sessionKeyAddr}</span>
      </div>
      <div class="session-chip">
        <span class="k">{i18n.t('janken.session.expires')}</span>
        <span class="v">{sessionRemainingLabel}</span>
      </div>
      <div class="session-chip">
        <span class="k">{i18n.t('janken.session.gas')}</span>
        <span class="v">{Number(formatEther(sessionGas)).toFixed(4)} ETH</span>
      </div>
    </div>
    <div class="session-actions">
      {#if !sessionActive}
        <button class="s-btn primary" onclick={openSessionModal}>
          {i18n.t('janken.session.start')}
        </button>
      {:else}
        <button class="s-btn" onclick={topUp}>{i18n.t('janken.session.topup')}</button>
      {/if}
      {#if sessionActive || sessionCredits > 0n}
        <button class="s-btn warn" onclick={endSession}>
          {i18n.t('janken.session.end')}
        </button>
      {/if}
    </div>
  </div>

  <!-- Tabs -->
  <div class="dfi-tabs" role="tablist">
    <button
      class="dfi-tab"
      class:active={activeTab === 'play'}
      onclick={() => (activeTab = 'play')}
    >
      {i18n.t('janken.tab.play')}
    </button>
    <button
      class="dfi-tab"
      class:active={activeTab === 'liquidity'}
      onclick={() => (activeTab = 'liquidity')}
    >
      {i18n.t('janken.tab.liquidity')}
    </button>
  </div>

  <!-- Play tab -->
  {#if activeTab === 'play'}
    <div class="tab-panel active">
      <div class="play-grid">
        <div class="panel cabinet-wrap">
          <div class="arcade-cabinet">
            <div class="cabinet-marquee">
              <span class="ml"></span><span class="ml"></span><span class="ml"></span>
              <span class="mt">JANKENMAN</span>
              <span class="ml"></span><span class="ml"></span><span class="ml"></span>
            </div>
            <div class="cabinet-screen">
              <div class="jk-stage">
                <div class="jk-pointer"></div>
                <div
                  class="jk-ring"
                  style="transform: rotate({wheelRotation}deg); transition: transform {wheelTransitionMs}ms cubic-bezier(0.18, 0.9, 0.24, 1);"
                >
                  <svg viewBox="0 0 200 200">
                    {#each wheelLabels as l}
                      <text
                        x="100"
                        y="28"
                        text-anchor="middle"
                        dominant-baseline="middle"
                        fill="#ffffff"
                        font-weight="800"
                        font-size="17"
                        font-family="Fredoka, sans-serif"
                        transform="rotate({l.angle} 100 100)"
                        style="paint-order: stroke; stroke: rgba(0,0,0,0.35); stroke-width: 1px;"
                      >
                        {l.m}×
                      </text>
                    {/each}
                  </svg>
                </div>
                <div class="jk-hub-ring"></div>
                <div class="jk-display {displayCycling ? 'cycling' : ''} {displayResultClass}">
                  <span class="jk-display-emoji">{displayEmoji}</span>
                </div>
              </div>
              <div class="status-line {statusKind}">
                <span class="status-dot"></span>
                {#if statusHtml}
                  <span class="status-text">{@html statusText}</span>
                {:else}
                  <span class="status-text">{statusText || i18n.t('janken.ready')}</span>
                {/if}
              </div>
            </div>
            <div class="cabinet-controls">
              <button
                class="arcade-btn rock"
                class:selected={selectedHand === 0}
                disabled={busy}
                onclick={() => setHand(0)}
              >
                <span class="cap">✊</span><span class="tab">{i18n.t('janken.rock')}</span>
              </button>
              <button
                class="arcade-btn paper"
                class:selected={selectedHand === 1}
                disabled={busy}
                onclick={() => setHand(1)}
              >
                <span class="cap">✋</span><span class="tab">{i18n.t('janken.paper')}</span>
              </button>
              <button
                class="arcade-btn sci"
                class:selected={selectedHand === 2}
                disabled={busy}
                onclick={() => setHand(2)}
              >
                <span class="cap">✌️</span><span class="tab">{i18n.t('janken.scissors')}</span>
              </button>
            </div>
          </div>
        </div>

        <div class="panel dim">
          <div class="h">
            <h3>{i18n.t('janken.slip')}</h3>
            <span class="tag">{i18n.t('janken.slip.tag')}</span>
          </div>
          <div class="slip-body">
            <div class="input-row">
              <input type="number" min="0.001" step="0.001" bind:value={betEth} />
              <span class="unit">ETH</span>
            </div>
            <div class="preset-row">
              {#each ['0.001', '0.01', '0.05', '0.1', '0.5'] as p}
                <button class="preset" onclick={() => preset(p)}>{p}</button>
              {/each}
            </div>

            <div class="payout-table">
              <div class="hdr">
                <span>{i18n.t('janken.slip.payout')}</span>
                <span>{i18n.t('janken.slip.odds')}</span>
              </div>
              {#each MULTS as { m, p }}
                <div class="row">
                  <span class="m">{m}×</span>
                  <span class="amt">{fmt(betNum * m)} ETH</span>
                  <span class="p">{p}%</span>
                </div>
              {/each}
              <div class="ev">
                <span>{i18n.t('janken.slip.ev')}</span>
                <span class="val" class:neg={evNum < 0}>{fmt(evNum)} ETH</span>
              </div>
            </div>

            <button class="big-play-btn" disabled={playDisabled} onclick={play}>
              <span>{i18n.t('janken.playBtn')}</span>
              <span>→</span>
            </button>

            <div class="defi-note">{@html i18n.t('janken.defiShort')}</div>
          </div>
        </div>
      </div>

      <div class="panel" style="margin-top: 18px">
        <div class="h">
          <h3>{i18n.t('janken.dist')}</h3>
          <span class="tag">E[M|win] = 1.79 · EV = -7%</span>
        </div>
        <div class="dist-list">
          <div class="dist-row m1">
            <span class="m">1×</span>
            <div class="bar"><span style="width: 100%"></span></div>
            <span class="pct">70%</span>
          </div>
          <div class="dist-row m2">
            <span class="m">2×</span>
            <div class="bar"><span style="width: 25.7%"></span></div>
            <span class="pct">18%</span>
          </div>
          <div class="dist-row m4">
            <span class="m">4×</span>
            <div class="bar"><span style="width: 11.4%"></span></div>
            <span class="pct">8%</span>
          </div>
          <div class="dist-row m7">
            <span class="m">7×</span>
            <div class="bar"><span style="width: 4.3%"></span></div>
            <span class="pct">3%</span>
          </div>
          <div class="dist-row m20">
            <span class="m">20×</span>
            <div class="bar"><span style="width: 1.4%"></span></div>
            <span class="pct">1%</span>
          </div>
        </div>
      </div>
    </div>
  {/if}

  <!-- Liquidity tab -->
  {#if activeTab === 'liquidity'}
    <div class="tab-panel active">
      <div class="liq-grid">
        <div class="panel">
          <div class="h">
            <h3>{i18n.t('janken.yourPos')}</h3>
            <span class="tag">{posPct}</span>
          </div>
          <div class="position-card">
            <div class="pos-chip">
              <span class="k">{i18n.t('janken.myShares')}</span>
              <span class="v">{posShares}</span>
            </div>
            <div class="pos-chip">
              <span class="k">{i18n.t('janken.myClaim')}</span>
              <span class="v">
                {posClaimEth} <span style="font-size: 11px; color: var(--ink-soft);">ETH</span>
              </span>
            </div>
            <div class="pos-chip">
              <span class="k">{i18n.t('janken.poolShare')}</span>
              <span class="v">{posPct}</span>
            </div>
          </div>

          <div style="margin-top: 14px">
            <div class="pool-head">
              <span>{i18n.t('janken.poolBreakdown')}</span>
              <span>{poolTotal} ETH TVL</span>
            </div>
            <div class="pool-bar">
              <div class="mine" style="width: {poolBarMine}%"></div>
              <div class="rest" style="width: {100 - poolBarMine}%"></div>
            </div>
            <div class="pool-foot">
              <span>you {poolYou} ETH</span>
              <span>others {poolOthers} ETH</span>
            </div>
          </div>

          <div class="defi-note" style="margin-top: 14px">
            {@html i18n.t('janken.defiNote')}
          </div>
        </div>

        <div class="panel dim">
          <div class="h">
            <h3>{i18n.t('janken.manage')}</h3>
            <span class="tag">{i18n.t('janken.manage.tag')}</span>
          </div>
          <div class="lp-form">
            <div>
              <div class="lp-hint">{i18n.t('janken.depositLabel')}</div>
              <div class="input-row">
                <input type="number" min="0.001" step="0.001" bind:value={lpAmount} />
                <span class="unit">ETH</span>
              </div>
              <div class="lp-hint">{depositPreview}</div>
              <button
                class="big-play-btn"
                style="background: var(--mint-deep); color: var(--ink); margin-top: 6px"
                onclick={lpDeposit}
              >
                <span>{i18n.t('janken.lpDeposit')}</span>
              </button>
            </div>
            <hr />
            <div>
              <div class="lp-hint">{i18n.t('janken.withdrawLabel')}</div>
              <div class="input-row">
                <input
                  type="number"
                  min="0"
                  step="1"
                  placeholder="shares"
                  bind:value={lpWithdrawShares}
                />
                <button class="preset" onclick={lpMax}>{i18n.t('janken.max')}</button>
              </div>
              <div class="lp-hint">{withdrawPreview}</div>
              <button
                class="big-play-btn"
                style="background: var(--coral-deep); color: var(--ink); margin-top: 6px"
                onclick={lpWithdraw}
              >
                <span>{i18n.t('janken.lpWithdraw')}</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  {/if}

  <!-- Recent rounds -->
  <div class="panel">
    <div class="h">
      <h3>{i18n.t('janken.recent')}</h3>
      <span class="tag">{history.length}</span>
    </div>
    <table class="rounds-table">
      <thead>
        <tr>
          <th>{i18n.t('janken.col.outcome')}</th>
          <th>{i18n.t('janken.col.hand')}</th>
          <th>{i18n.t('janken.col.bet')}</th>
          <th>{i18n.t('janken.col.payout')}</th>
          <th>{i18n.t('janken.col.tx')}</th>
        </tr>
      </thead>
      <tbody>
        {#if history.length === 0}
          <tr class="empty">
            <td colspan="5">{i18n.t('janken.noRounds')}</td>
          </tr>
        {:else}
          {#each history as { result: r, hash } (hash)}
            <tr>
              <td>
                <span
                  class="outcome {r.outcome === 2 ? 'win' : r.outcome === 1 ? 'draw' : 'lose'}"
                >
                  {r.outcome === 2 ? `win ${r.mult}×` : r.outcome === 1 ? 'draw' : 'lose'}
                </span>
              </td>
              <td>
                {HAND_NAMES[r.pHand]}
                <span style="color: var(--ink-faint)">vs</span>
                {HAND_NAMES[r.hHand]}
              </td>
              <td>{formatEther(r.bet)} ETH</td>
              <td>
                {r.outcome === 2
                  ? `+${formatEther(r.payout)}`
                  : r.outcome === 1
                    ? '±0'
                    : `−${formatEther(r.bet)}`}
                ETH
              </td>
              <td><span class="hash">{hash.slice(0, 10)}…</span></td>
            </tr>
          {/each}
        {/if}
      </tbody>
    </table>
    <div style="margin-top: 12px">
      <div class="raw-label">{i18n.t('common.raw')}</div>
      <div class="hex-block">{randHex}</div>
    </div>
  </div>
</div>

<!-- Modal -->
{#if modalOpen}
  <div class="modal-backdrop active" onclick={() => (modalOpen = false)}>
    <div class="modal" onclick={(e) => e.stopPropagation()} role="dialog">
      <h3>{i18n.t('janken.modal.title')}</h3>
      <p class="sub">{@html i18n.t('janken.modal.sub')}</p>

      <div class="field">
        <label>{i18n.t('janken.modal.deposit')}</label>
        <div class="input-row">
          <input type="number" min="0.001" step="0.01" bind:value={modalDeposit} />
          <span class="unit">ETH</span>
        </div>
      </div>

      <div class="field">
        <label>{i18n.t('janken.modal.gas')}</label>
        <div class="input-row">
          <input type="number" min="0.005" step="0.005" bind:value={modalGas} />
          <span class="unit">ETH</span>
        </div>
        <span class="hint">{i18n.t('janken.modal.gasHint')}</span>
      </div>

      <div class="field">
        <label>{i18n.t('janken.modal.duration')}</label>
        <div class="input-row">
          <input type="number" min="1" max="24" step="1" bind:value={modalHours} />
          <span class="unit">hours</span>
        </div>
      </div>

      <div class="field">
        <label>{i18n.t('janken.modal.key')}</label>
        <span class="hint" style="font-size: 12px; color: var(--ink);">
          {sessionKeyFull}
        </span>
      </div>

      <div class="actions">
        <button class="s-btn" onclick={() => (modalOpen = false)}>
          {i18n.t('janken.modal.cancel')}
        </button>
        <button class="s-btn primary" disabled={modalSigning} onclick={startSession}>
          {modalSigning ? i18n.t('janken.modal.signing') : i18n.t('janken.modal.confirm')}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  :root {
    --accent: var(--tk-blue);
    --accent-deep: var(--tk-blue-deep);
  }

  :global(body > #topbar) {
    position: sticky;
    top: 0;
    z-index: 50;
    background: rgba(11, 15, 23, 0.85);
    backdrop-filter: saturate(140%) blur(12px);
    -webkit-backdrop-filter: saturate(140%) blur(12px);
    padding: 0 32px;
  }
  :global(body > #topbar .tokamak-topbar) {
    margin: 0 auto;
  }

  .dfi-shell {
    max-width: 1120px;
    margin: 0 auto;
    padding: 0 32px;
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .dfi-head {
    display: flex;
    align-items: center;
    gap: 14px;
    flex-wrap: wrap;
  }
  .dfi-head .mascot {
    width: 60px;
    height: 60px;
    border-radius: 16px;
    background: var(--tk-blue);
    border: 2.5px solid var(--ink);
    box-shadow: 3px 3px 0 var(--ink);
    display: grid;
    place-items: center;
    flex-shrink: 0;
  }
  .dfi-head h2 {
    font-family: 'Fredoka', sans-serif;
    font-size: 28px;
    letter-spacing: -0.02em;
    margin-right: auto;
  }
  .dfi-head .contract-pill {
    font-family: 'JetBrains Mono', monospace;
    font-size: 11px;
    background: var(--paper);
    border: 2px solid var(--ink);
    box-shadow: 2px 2px 0 var(--ink);
    padding: 6px 10px;
    border-radius: 999px;
    color: var(--ink-soft);
  }
  .dfi-head .contract-pill b {
    color: var(--ink);
    font-weight: 600;
    margin-right: 6px;
  }

  .kpi-strip {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
    gap: 14px;
  }
  .kpi {
    background: var(--paper);
    border: 3px solid var(--ink);
    box-shadow: 4px 4px 0 var(--ink);
    border-radius: 16px;
    padding: 14px 18px;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .kpi .k {
    font-family: 'Fredoka', sans-serif;
    font-size: 11px;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    color: var(--ink-soft);
  }
  .kpi .v {
    font-family: 'JetBrains Mono', monospace;
    font-size: 22px;
    font-weight: 600;
    color: var(--ink);
    letter-spacing: -0.01em;
  }
  .kpi .v .u {
    font-size: 13px;
    color: var(--ink-soft);
    margin-left: 4px;
    font-weight: 500;
  }
  .kpi.blue {
    background: var(--tk-blue);
    color: #fff;
  }
  .kpi.blue .k {
    color: rgba(255, 255, 255, 0.75);
  }
  .kpi.blue .v {
    color: #fff;
  }
  .kpi.blue .v .u {
    color: rgba(255, 255, 255, 0.75);
  }
  .kpi.vrf {
    background: #0e1740;
    color: #7fe3ad;
    position: relative;
    overflow: hidden;
  }
  .kpi.vrf::before {
    content: '';
    position: absolute;
    inset: 0;
    background: radial-gradient(circle at 80% 20%, rgba(127, 227, 173, 0.18), transparent 60%);
  }
  .kpi.vrf > * {
    position: relative;
  }
  .kpi.vrf .k {
    color: rgba(127, 227, 173, 0.85);
  }
  .kpi.vrf .v {
    color: #e8fff3;
    text-shadow: 0 0 10px rgba(127, 227, 173, 0.5);
  }
  .kpi.vrf .v .u {
    color: rgba(127, 227, 173, 0.7);
  }
  .kpi.vrf .pulse-dot {
    position: absolute;
    top: 14px;
    right: 14px;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #7fe3ad;
    box-shadow: 0 0 10px #7fe3ad;
    animation: vrf-pulse 1.2s infinite;
  }
  @keyframes vrf-pulse {
    0%,
    100% {
      opacity: 0.35;
      transform: scale(0.8);
    }
    50% {
      opacity: 1;
      transform: scale(1.2);
    }
  }

  .session-strip {
    border: 3px solid var(--ink);
    border-radius: 16px;
    background: var(--paper);
    box-shadow: 4px 4px 0 var(--ink);
    padding: 14px 18px;
    display: flex;
    gap: 16px;
    align-items: center;
    flex-wrap: wrap;
  }
  .session-strip .status-badge {
    font-family: 'Fredoka', sans-serif;
    font-size: 11px;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    padding: 5px 11px;
    border-radius: 999px;
    border: 2px solid var(--ink);
    background: var(--butter);
    color: var(--ink);
    flex-shrink: 0;
  }
  .session-strip .status-badge.idle {
    background: var(--butter);
  }
  .session-strip .status-badge.active {
    background: var(--mint);
  }
  .session-strip .status-badge.expired {
    background: var(--coral);
  }
  .session-chips {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
    flex: 1;
    font-family: 'JetBrains Mono', monospace;
    font-size: 12px;
  }
  .session-chip {
    background: var(--paper-2);
    border: 2px solid var(--ink);
    border-radius: 10px;
    padding: 6px 10px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 110px;
  }
  .session-chip .k {
    font-family: 'Fredoka', sans-serif;
    font-size: 9px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--ink-soft);
    font-weight: 700;
  }
  .session-chip .v {
    font-weight: 600;
    color: var(--ink);
    font-size: 13px;
  }
  .session-chip.hl {
    background: var(--tk-blue);
    color: #fff;
    border-color: #000;
  }
  .session-chip.hl .k {
    color: rgba(255, 255, 255, 0.7);
  }
  .session-chip.hl .v {
    color: #fff;
  }
  .session-actions {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
  }
  .s-btn {
    font-family: 'Fredoka', sans-serif;
    font-weight: 600;
    font-size: 12px;
    letter-spacing: 0.04em;
    padding: 8px 14px;
    border-radius: 10px;
    border: 2px solid var(--ink);
    box-shadow: 2px 2px 0 var(--ink);
    background: var(--paper);
    color: var(--ink);
    cursor: pointer;
    transition:
      transform 0.08s ease,
      box-shadow 0.08s ease,
      background 0.15s ease;
  }
  .s-btn:hover {
    transform: translate(-1px, -1px);
    box-shadow: 3px 3px 0 var(--ink);
  }
  .s-btn:active {
    transform: translate(1px, 1px);
    box-shadow: 1px 1px 0 var(--ink);
  }
  .s-btn.primary {
    background: var(--tk-blue);
    color: #fff;
  }
  .s-btn.primary:hover {
    background: var(--tk-blue-deep);
  }
  .s-btn.warn {
    background: var(--coral);
  }

  .dfi-tabs {
    display: inline-flex;
    padding: 4px;
    border: 3px solid var(--ink);
    border-radius: 999px;
    background: var(--paper);
    box-shadow: 3px 3px 0 var(--ink);
    gap: 4px;
    align-self: flex-start;
  }
  .dfi-tab {
    appearance: none;
    border: 0;
    padding: 9px 20px;
    border-radius: 999px;
    font-family: 'Fredoka', sans-serif;
    font-weight: 600;
    font-size: 14px;
    color: var(--ink-soft);
    background: transparent;
    cursor: pointer;
    transition:
      background 0.15s ease,
      color 0.15s ease;
  }
  .dfi-tab.active {
    background: var(--ink);
    color: #fff;
  }
  .dfi-tab:hover:not(.active) {
    color: var(--ink);
  }

  .play-grid,
  .liq-grid {
    display: grid;
    grid-template-columns: minmax(0, 1.2fr) minmax(320px, 1fr);
    gap: 18px;
  }
  @media (max-width: 820px) {
    .play-grid,
    .liq-grid {
      grid-template-columns: 1fr;
    }
  }

  .panel {
    background: var(--paper);
    border: 3px solid var(--ink);
    border-radius: 20px;
    padding: 22px;
    box-shadow: 5px 5px 0 var(--ink);
  }
  .panel.dim {
    background: var(--paper-2);
  }
  .panel .h {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 14px;
  }
  .panel .h h3 {
    font-family: 'Fredoka', sans-serif;
    font-size: 16px;
    font-weight: 700;
  }
  .panel .h .tag {
    font-family: 'JetBrains Mono', monospace;
    font-size: 11px;
    color: var(--ink-soft);
  }
  .panel.cabinet-wrap {
    background: transparent;
    border: 0;
    box-shadow: none;
    padding: 0;
  }

  /* Arcade cabinet */
  .arcade-cabinet {
    background: linear-gradient(180deg, #1a2352 0%, #0e1740 100%);
    border: 3px solid #000;
    border-radius: 22px;
    padding: 8px;
    box-shadow:
      5px 5px 0 #000,
      inset 0 0 0 2px rgba(111, 168, 255, 0.15);
    position: relative;
  }
  .cabinet-marquee {
    background: linear-gradient(180deg, var(--tk-blue) 0%, var(--tk-blue-deep) 100%);
    border: 2px solid #000;
    border-radius: 12px 12px 8px 8px;
    padding: 10px 16px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
  }
  .cabinet-marquee .mt {
    font-family: 'Fredoka', sans-serif;
    font-weight: 700;
    letter-spacing: 0.32em;
    font-size: 15px;
    color: #fff;
    text-shadow:
      0 0 10px rgba(255, 255, 255, 0.6),
      0 0 18px rgba(111, 168, 255, 0.6);
  }
  .cabinet-marquee .ml {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: #ffe29a;
    box-shadow:
      0 0 10px #ffe29a,
      0 0 4px #fff;
    animation: marquee-blink 1.3s infinite;
  }
  .cabinet-marquee .ml:nth-child(1) {
    animation-delay: 0s;
  }
  .cabinet-marquee .ml:nth-child(2) {
    animation-delay: 0.15s;
  }
  .cabinet-marquee .ml:nth-child(3) {
    animation-delay: 0.3s;
  }
  .cabinet-marquee .ml:nth-child(5) {
    animation-delay: 0.45s;
  }
  .cabinet-marquee .ml:nth-child(6) {
    animation-delay: 0.6s;
  }
  .cabinet-marquee .ml:nth-child(7) {
    animation-delay: 0.75s;
  }
  @keyframes marquee-blink {
    0%,
    100% {
      opacity: 0.35;
      transform: scale(0.8);
    }
    50% {
      opacity: 1;
      transform: scale(1.15);
    }
  }

  .cabinet-screen {
    margin: 8px 4px 4px;
    background: radial-gradient(ellipse at center, #0d1a40 0%, #050b22 100%);
    border: 2px solid #000;
    border-radius: 10px;
    padding: 20px 18px 16px;
    min-height: 300px;
    position: relative;
    overflow: hidden;
  }
  .cabinet-screen::before {
    content: '';
    position: absolute;
    inset: 0;
    background: repeating-linear-gradient(
      0deg,
      rgba(255, 255, 255, 0.025) 0px,
      rgba(255, 255, 255, 0.025) 1px,
      transparent 1px,
      transparent 3px
    );
    pointer-events: none;
    z-index: 2;
  }
  .cabinet-screen::after {
    content: '';
    position: absolute;
    inset: 0;
    box-shadow: inset 0 0 80px rgba(0, 0, 0, 0.6);
    border-radius: 10px;
    pointer-events: none;
    z-index: 2;
  }

  .jk-stage {
    position: relative;
    z-index: 1;
    width: min(320px, 78vw);
    aspect-ratio: 1;
    margin: 0 auto;
  }
  .jk-pointer {
    position: absolute;
    top: -2px;
    left: 50%;
    transform: translateX(-50%);
    width: 0;
    height: 0;
    border-left: 12px solid transparent;
    border-right: 12px solid transparent;
    border-top: 22px solid #ffe29a;
    filter: drop-shadow(0 0 10px rgba(255, 226, 154, 0.9));
    z-index: 10;
  }
  .jk-ring {
    position: absolute;
    inset: 0;
    border-radius: 50%;
    border: 4px solid #000;
    box-shadow:
      0 0 0 3px rgba(0, 0, 0, 0.2),
      0 0 26px rgba(31, 111, 235, 0.45),
      inset 0 0 20px rgba(0, 0, 0, 0.25);
    background: conic-gradient(
      from -18deg,
      #ffd3df 0 36deg,
      #ffc0d0 36deg 72deg,
      #ffd3df 72deg 108deg,
      #ffe29a 108deg 144deg,
      #ffd3df 144deg 180deg,
      #ffc0d0 180deg 216deg,
      #d7b5f5 216deg 252deg,
      #ffd3df 252deg 288deg,
      #ffc0d0 288deg 324deg,
      #ff8a7e 324deg 360deg
    );
  }
  .jk-ring svg {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }
  .jk-hub-ring {
    position: absolute;
    inset: 28%;
    border-radius: 50%;
    background: radial-gradient(circle at 35% 30%, #cff0db 0%, #b5ead7 60%, #8fd6b9 100%);
    border: 3px solid #000;
    box-shadow:
      0 0 16px rgba(143, 214, 185, 0.35),
      inset 0 0 14px rgba(0, 0, 0, 0.15);
    z-index: 2;
  }
  .jk-display {
    position: absolute;
    inset: 37%;
    border-radius: 10px;
    background: radial-gradient(circle at 50% 50%, #3a0c0c 0%, #150303 85%);
    border: 3px solid #000;
    box-shadow:
      inset 0 0 24px rgba(255, 40, 40, 0.35),
      0 0 22px rgba(255, 40, 40, 0.4);
    display: grid;
    place-items: center;
    z-index: 3;
    overflow: hidden;
  }
  .jk-display::before {
    content: '';
    position: absolute;
    inset: 0;
    background-image:
      repeating-linear-gradient(0deg, transparent 0 2px, rgba(255, 0, 0, 0.12) 2px 3px),
      repeating-linear-gradient(90deg, transparent 0 2px, rgba(255, 0, 0, 0.12) 2px 3px);
    mix-blend-mode: screen;
    pointer-events: none;
  }
  .jk-display-emoji {
    position: relative;
    z-index: 1;
    font-size: clamp(44px, 9.5vw, 64px);
    line-height: 1;
    filter: drop-shadow(0 0 6px #ff2a2a) drop-shadow(0 0 12px #ff4040) saturate(1.4);
    transition: transform 0.08s ease;
  }
  .jk-display.cycling .jk-display-emoji {
    animation: display-flicker 0.12s infinite;
  }
  @keyframes display-flicker {
    0%,
    100% {
      opacity: 1;
    }
    50% {
      opacity: 0.82;
    }
  }
  .jk-display.result-win {
    box-shadow:
      inset 0 0 24px rgba(127, 227, 173, 0.45),
      0 0 22px rgba(127, 227, 173, 0.55);
  }
  .jk-display.result-lose {
    box-shadow:
      inset 0 0 24px rgba(255, 138, 138, 0.45),
      0 0 22px rgba(255, 138, 138, 0.55);
  }
  .jk-display.result-draw {
    box-shadow:
      inset 0 0 24px rgba(255, 226, 154, 0.45),
      0 0 22px rgba(255, 226, 154, 0.55);
  }

  .status-line {
    position: relative;
    z-index: 3;
    margin-top: 14px;
    background: #000;
    border: 1px solid rgba(181, 234, 215, 0.3);
    border-radius: 6px;
    padding: 10px 14px;
    font-family: 'JetBrains Mono', monospace;
    font-size: 12px;
    font-weight: 600;
    color: #7fe3ad;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    text-shadow: 0 0 10px currentColor;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    min-height: 38px;
    text-align: center;
  }
  .status-line .status-dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: currentColor;
    box-shadow: 0 0 10px currentColor;
    animation: dot-blink 1s infinite;
    flex-shrink: 0;
  }
  @keyframes dot-blink {
    50% {
      opacity: 0.25;
    }
  }
  .status-line :global(b) {
    color: #fff;
    font-weight: 700;
    text-shadow: 0 0 10px currentColor;
  }
  .status-line.win {
    color: #7fe3ad;
    border-color: rgba(127, 227, 173, 0.4);
  }
  .status-line.lose {
    color: #ff8a8a;
    border-color: rgba(255, 138, 138, 0.4);
  }
  .status-line.draw {
    color: #ffe29a;
    border-color: rgba(255, 226, 154, 0.4);
  }

  .cabinet-controls {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 10px;
    padding: 12px;
    margin: 4px;
    background: linear-gradient(180deg, #3b4680 0%, #2b3558 100%);
    border-radius: 10px;
    border: 2px solid #000;
  }
  .arcade-btn {
    appearance: none;
    cursor: pointer;
    height: 92px;
    border-radius: 14px;
    border: 3px solid #000;
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 4px;
    font-family: 'Fredoka', sans-serif;
    font-weight: 700;
    letter-spacing: 0.14em;
    box-shadow:
      0 6px 0 rgba(0, 0, 0, 0.6),
      inset 0 6px 12px rgba(255, 255, 255, 0.25),
      inset 0 -6px 10px rgba(0, 0, 0, 0.18);
    transition:
      transform 0.08s ease,
      box-shadow 0.08s ease;
    color: var(--ink);
  }
  .arcade-btn.rock {
    background: linear-gradient(180deg, #ffa494 0%, #ff7b6a 100%);
  }
  .arcade-btn.paper {
    background: linear-gradient(180deg, #ffe29a 0%, #ffcb4d 100%);
  }
  .arcade-btn.sci {
    background: linear-gradient(180deg, #9dd3f5 0%, #5fb8e6 100%);
  }
  .arcade-btn:hover {
    filter: brightness(1.06);
  }
  .arcade-btn:active {
    transform: translateY(5px);
    box-shadow:
      0 1px 0 rgba(0, 0, 0, 0.6),
      inset 0 6px 12px rgba(255, 255, 255, 0.25),
      inset 0 -4px 10px rgba(0, 0, 0, 0.18);
  }
  .arcade-btn.selected {
    outline: 3px solid #ffe29a;
    outline-offset: 3px;
    box-shadow:
      0 6px 0 rgba(0, 0, 0, 0.6),
      inset 0 6px 12px rgba(255, 255, 255, 0.25),
      inset 0 -6px 10px rgba(0, 0, 0, 0.18),
      0 0 18px rgba(255, 226, 154, 0.8);
  }
  .arcade-btn:disabled {
    opacity: 0.55;
    cursor: not-allowed;
  }
  .arcade-btn .cap {
    font-size: 32px;
    line-height: 1;
    filter: drop-shadow(0 1px 0 rgba(0, 0, 0, 0.15));
  }
  .arcade-btn .tab {
    font-size: 11px;
  }

  .slip-body {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .input-row {
    display: flex;
    gap: 8px;
    align-items: center;
    background: var(--paper-2);
    border: 3px solid var(--ink);
    border-radius: 14px;
    padding: 10px 12px;
  }
  .input-row input[type='number'] {
    appearance: none;
    border: 0;
    background: transparent;
    outline: none;
    flex: 1;
    min-width: 0;
    font-family: 'JetBrains Mono', monospace;
    font-size: 22px;
    font-weight: 600;
    color: var(--ink);
  }
  .input-row .unit {
    font-family: 'Fredoka', sans-serif;
    font-weight: 600;
    color: var(--ink-soft);
    font-size: 14px;
  }
  .preset-row {
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
  }
  .preset {
    font-family: 'JetBrains Mono', monospace;
    font-size: 11px;
    font-weight: 500;
    padding: 6px 10px;
    border-radius: 999px;
    border: 2px solid var(--ink);
    background: var(--paper);
    box-shadow: 2px 2px 0 var(--ink);
    cursor: pointer;
    color: var(--ink);
  }
  .preset:hover {
    background: var(--butter);
  }

  .payout-table {
    font-family: 'JetBrains Mono', monospace;
    font-size: 12px;
    border: 2px dashed var(--ink-faint);
    border-radius: 12px;
    padding: 10px 12px;
    background: rgba(255, 255, 255, 0.5);
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .payout-table .hdr {
    display: flex;
    justify-content: space-between;
    color: var(--ink-soft);
    font-size: 10px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    font-weight: 700;
    padding-bottom: 4px;
    border-bottom: 1px solid var(--ink-faint);
  }
  .payout-table .row {
    display: grid;
    grid-template-columns: 34px 1fr auto;
    gap: 8px;
    align-items: center;
  }
  .payout-table .row .p {
    color: var(--ink-soft);
  }
  .payout-table .row .m {
    color: var(--ink);
    font-weight: 600;
  }
  .payout-table .row .amt {
    color: var(--tk-blue-deep);
    font-weight: 600;
  }
  .payout-table .ev {
    margin-top: 4px;
    padding-top: 6px;
    border-top: 1px solid var(--ink-faint);
    display: flex;
    justify-content: space-between;
    color: var(--ink-soft);
    font-size: 11px;
  }
  .payout-table .ev .val.neg {
    color: #c84a4a;
    font-weight: 600;
  }

  .big-play-btn {
    appearance: none;
    cursor: pointer;
    width: 100%;
    padding: 16px 18px;
    border-radius: 14px;
    border: 3px solid var(--ink);
    background: var(--tk-blue);
    color: #fff;
    font-family: 'Fredoka', sans-serif;
    font-weight: 700;
    font-size: 18px;
    box-shadow: 5px 5px 0 var(--ink);
    transition:
      transform 0.08s ease,
      box-shadow 0.08s ease,
      background 0.15s ease;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
  }
  .big-play-btn:hover {
    background: var(--tk-blue-deep);
    transform: translate(-1px, -1px);
    box-shadow: 6px 6px 0 var(--ink);
  }
  .big-play-btn:active {
    transform: translate(3px, 3px);
    box-shadow: 1px 1px 0 var(--ink);
  }
  .big-play-btn:disabled {
    background: var(--ink-faint);
    cursor: not-allowed;
    transform: none;
    box-shadow: 5px 5px 0 var(--ink);
  }

  .dist-list {
    display: flex;
    flex-direction: column;
    gap: 10px;
    font-family: 'JetBrains Mono', monospace;
    font-size: 12px;
  }
  .dist-row {
    display: grid;
    grid-template-columns: 46px 1fr 54px;
    gap: 10px;
    align-items: center;
  }
  .dist-row .m {
    font-weight: 700;
    color: var(--ink);
  }
  .dist-row .bar {
    height: 14px;
    border: 2px solid var(--ink);
    border-radius: 6px;
    background: var(--paper-2);
    position: relative;
    overflow: hidden;
  }
  .dist-row .bar span {
    display: block;
    height: 100%;
    background: linear-gradient(90deg, var(--tk-blue), var(--tk-blue-deep));
  }
  .dist-row.m1 .bar span {
    background: var(--sky-deep);
  }
  .dist-row.m2 .bar span {
    background: var(--mint-deep);
  }
  .dist-row.m4 .bar span {
    background: var(--butter-deep);
  }
  .dist-row.m7 .bar span {
    background: var(--lavender-deep);
  }
  .dist-row.m20 .bar span {
    background: var(--coral-deep);
  }
  .dist-row .pct {
    text-align: right;
    color: var(--ink-soft);
  }

  .rounds-table {
    width: 100%;
    font-family: 'JetBrains Mono', monospace;
    font-size: 12px;
    border-collapse: separate;
    border-spacing: 0 6px;
  }
  .rounds-table thead th {
    text-align: left;
    font-weight: 700;
    color: var(--ink-soft);
    font-size: 10px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    padding: 0 10px 4px;
    font-family: 'Fredoka', sans-serif;
  }
  .rounds-table tbody td {
    background: var(--paper);
    border-top: 2px solid var(--ink);
    border-bottom: 2px solid var(--ink);
    padding: 10px;
  }
  .rounds-table tbody td:first-child {
    border-left: 2px solid var(--ink);
    border-radius: 10px 0 0 10px;
  }
  .rounds-table tbody td:last-child {
    border-right: 2px solid var(--ink);
    border-radius: 0 10px 10px 0;
  }
  .rounds-table .outcome {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 999px;
    font-weight: 700;
    font-family: 'Fredoka', sans-serif;
    font-size: 11px;
  }
  .rounds-table .outcome.win {
    background: var(--mint);
    color: var(--ink);
  }
  .rounds-table .outcome.draw {
    background: var(--butter);
    color: var(--ink);
  }
  .rounds-table .outcome.lose {
    background: var(--coral);
    color: var(--ink);
  }
  .rounds-table .hash {
    color: var(--tk-blue-deep);
  }
  .rounds-table .empty td {
    text-align: center;
    color: var(--ink-faint);
    background: transparent;
    border: 2px dashed var(--ink-faint);
    border-radius: 10px;
    padding: 24px;
  }

  .position-card {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
    gap: 12px;
    margin-bottom: 14px;
  }
  .pos-chip {
    border: 2px solid var(--ink);
    border-radius: 12px;
    background: var(--paper-2);
    padding: 10px 14px;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .pos-chip .k {
    font-size: 10px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--ink-soft);
    font-family: 'Fredoka', sans-serif;
    font-weight: 700;
  }
  .pos-chip .v {
    font-family: 'JetBrains Mono', monospace;
    font-size: 16px;
    font-weight: 600;
    color: var(--ink);
  }

  .lp-form {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .lp-form hr {
    border: 0;
    border-top: 2px dashed var(--ink-faint);
    margin: 6px 0;
  }
  .lp-hint {
    font-family: 'JetBrains Mono', monospace;
    font-size: 11px;
    color: var(--ink-soft);
    padding: 2px 0;
  }

  .pool-bar {
    height: 24px;
    border: 2.5px solid var(--ink);
    border-radius: 999px;
    background: var(--paper);
    overflow: hidden;
    display: flex;
  }
  .pool-bar .mine {
    background: var(--tk-blue);
  }
  .pool-bar .rest {
    background: var(--paper-2);
  }
  .pool-head {
    display: flex;
    justify-content: space-between;
    font-family: 'Fredoka', sans-serif;
    font-size: 11px;
    color: var(--ink-soft);
    letter-spacing: 0.12em;
    text-transform: uppercase;
    margin-bottom: 6px;
  }
  .pool-foot {
    display: flex;
    justify-content: space-between;
    font-family: 'JetBrains Mono', monospace;
    font-size: 11px;
    color: var(--ink-soft);
    margin-top: 6px;
  }

  .defi-note {
    font-family: 'Nunito', sans-serif;
    font-size: 13px;
    color: var(--ink-soft);
    line-height: 1.6;
    padding: 12px 14px;
    border-left: 3px solid var(--tk-blue);
    background: rgba(31, 111, 235, 0.06);
    border-radius: 0 10px 10px 0;
  }
  .defi-note :global(b) {
    color: var(--ink);
  }

  .raw-label {
    font-family: 'Fredoka', sans-serif;
    font-size: 10px;
    color: var(--ink-soft);
    letter-spacing: 0.12em;
    text-transform: uppercase;
    margin-bottom: 6px;
  }
  .hex-block {
    font-family: 'JetBrains Mono', monospace;
    font-size: 10px;
    color: var(--ink-soft);
    word-break: break-all;
    line-height: 1.55;
    background: var(--paper-2);
    border: 2px dashed var(--ink-faint);
    padding: 8px 12px;
    border-radius: 10px;
  }

  .modal-backdrop {
    position: fixed;
    inset: 0;
    z-index: 50;
    background: rgba(10, 18, 48, 0.6);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 20px;
  }
  .modal {
    background: var(--paper);
    border: 3px solid var(--ink);
    border-radius: 22px;
    box-shadow: 6px 6px 0 var(--ink);
    width: 100%;
    max-width: 440px;
    padding: 24px;
  }
  .modal h3 {
    font-family: 'Fredoka', sans-serif;
    font-size: 20px;
    font-weight: 700;
    margin-bottom: 4px;
  }
  .modal .sub {
    font-size: 13px;
    color: var(--ink-soft);
    margin-bottom: 18px;
    line-height: 1.55;
  }
  .modal .field {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-bottom: 14px;
  }
  .modal .field label {
    font-family: 'Fredoka', sans-serif;
    font-size: 11px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--ink-soft);
    font-weight: 700;
  }
  .modal .hint {
    font-family: 'JetBrains Mono', monospace;
    font-size: 11px;
    color: var(--ink-soft);
  }
  .modal .actions {
    display: flex;
    gap: 10px;
    justify-content: flex-end;
    margin-top: 18px;
  }

  .tokamak-back {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-family: var(--font-sans);
    font-size: 12px;
    font-weight: 600;
    color: var(--ink-soft);
    text-decoration: none;
    margin-bottom: 8px;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    transition: color 0.15s ease;
    align-self: flex-start;
  }
  .tokamak-back:hover {
    color: var(--tk-blue);
    text-decoration: none;
  }
</style>
