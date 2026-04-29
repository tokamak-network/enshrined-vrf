<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { decodeEventLog, formatEther, parseEther, type Hash } from 'viem';
  import { i18n } from '$lib/i18n.svelte';
  import { wallet, pub, shortAddr } from '$lib/wallet.svelte';
  import { CONFIG } from '$lib/config';
  import LangToggle from '$lib/components/LangToggle.svelte';
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
  import Cabinet2D from '$lib/jankenman/Cabinet2D.svelte';

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

  // Sidebar navigation
  let activeView = $state<'game' | 'lp' | 'leaderboard'>('game');

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
      setStatus('lose', 'NO ACTIVE SESSION — start a session above');
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
      history = [{ result, hash }, ...history].slice(0, 10);
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
      setStatus('draw', `DRAW · ${formatEther(bet)} ETH refunded`);
    } else if (outcome === 0) {
      setStatus('lose', `LOSS · −${formatEther(bet)} ETH → pool`);
    } else {
      setStatus('win', `WIN ${mult}× · +${formatEther(payout)} ETH`);
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

  async function onConnect() {
    if (wallet.account) return;
    try {
      await wallet.connect();
    } catch (err: any) {
      console.error('[connect]', err);
      alert(err?.message ?? String(err));
    }
  }

  // ─── Derived ──────────────────────────────────────────────────────
  const betNum = $derived(Number(betEth || '0'));
  const evNum = $derived(-0.07 * betNum);
  const expectedPayoutOnWin = $derived(betNum * 1.79); // E[M|win] = 1.79
  const fmt = (x: number) => (x >= 100 ? x.toFixed(2) : x >= 10 ? x.toFixed(3) : x.toFixed(4));
  const playDisabled = $derived(busy || selectedHand === null || !sessionActive);
  const sessionRemainingLabel = $derived.by(() => {
    if (!sessionActive) return '—';
    const s = sessionRemaining;
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
  });
  const sessionKeyAddr = $derived(session ? shortAddr(session.account.address) : '—');
  const sessionKeyFull = $derived(session ? session.account.address : '—');
  const connectLabel = $derived.by(() => {
    if (wallet.connecting) return i18n.t('common.connecting');
    if (wallet.account) return shortAddr(wallet.account);
    if (!wallet.hasProvider) return i18n.t('common.noWallet');
    return i18n.t('common.connect');
  });

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

  // ─── Sidebar nav icons (inline SVG, currentColor) ─────────────────
  const navGameIcon = `
<svg viewBox="0 0 18 18" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round">
  <path d="M5 3 L15 9 L5 15 z" fill="currentColor"/>
</svg>`;
  const navLpIcon = `
<svg viewBox="0 0 18 18" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round">
  <path d="M9 2 C 5.5 6.5, 4 9, 4 11.5 a 5 5 0 0 0 10 0 C 14 9, 12.5 6.5, 9 2 z"/>
</svg>`;
  const navLbIcon = `
<svg viewBox="0 0 18 18" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round">
  <path d="M5 3 h8 v3 a4 4 0 0 1 -8 0 z"/>
  <path d="M3 4 h2 v2 a 2 2 0 0 1 -2 0 z M13 4 h2 v2 a 2 2 0 0 1 -2 0 z"/>
  <path d="M7 11 h4 l-0.5 4 h-3 z"/>
  <path d="M5.5 15 h7"/>
</svg>`;
</script>

<svelte:head>
  <title>{i18n.t('janken.title')}</title>
</svelte:head>

<div class="gmx-shell">
  <aside class="sb">
    <a class="sb-brand" href="/">
      <span class="sb-mark">{@html jankenMascot({ size: 26 })}</span>
      <span class="sb-name">Jankenman</span>
    </a>

    <nav class="sb-nav">
      <button
        class="sb-item"
        class:active={activeView === 'game'}
        onclick={() => (activeView = 'game')}
      >
        <span class="sb-icon">{@html navGameIcon}</span>
        <span>{i18n.t('janken.nav.game')}</span>
      </button>
      <button
        class="sb-item"
        class:active={activeView === 'lp'}
        onclick={() => (activeView = 'lp')}
      >
        <span class="sb-icon">{@html navLpIcon}</span>
        <span>{i18n.t('janken.nav.lp')}</span>
      </button>
      <button
        class="sb-item"
        class:active={activeView === 'leaderboard'}
        onclick={() => (activeView = 'leaderboard')}
      >
        <span class="sb-icon">{@html navLbIcon}</span>
        <span>{i18n.t('janken.nav.leaderboard')}</span>
      </button>
    </nav>

    <div class="sb-foot">
      <LangToggle />
      <a class="sb-back" href="/">←</a>
    </div>
  </aside>

  <div class="gmx-main">
    <header class="topbar">
      <div class="pair">
        <span class="pair-name">Jankenman</span>
      </div>

      <div class="topbar-metrics">
        <div class="metric">
          <span class="m-k">POOL TVL</span>
          <span class="m-v">{kpiTvl}<span class="m-u">ETH</span></span>
        </div>
        <div class="metric">
          <span class="m-k">HOUSE EDGE</span>
          <span class="m-v">7.00<span class="m-u">%</span></span>
        </div>
        <div class="metric">
          <span class="m-k">SHARE PRICE</span>
          <span class="m-v">{kpiPrice}<span class="m-u">Ξ</span></span>
        </div>
        <div class="metric vrf-metric">
          <span class="m-k">VRF COMMIT</span>
          <span class="m-v">#{kpiVrf}</span>
        </div>
      </div>

      <button
        class="connect"
        disabled={wallet.connecting}
        onclick={onConnect}
      >
        {connectLabel}
      </button>
    </header>

    <main class="content">
      {#if activeView === 'game'}
        <section class="game-grid">
          <!-- LEFT: 2D Korean-arcade cabinet (the "chart" area) -->
          <div class="board-panel">
            <div class="cabinet-host">
              <Cabinet2D
                targetRotationDeg={wheelRotation}
                {displayEmoji}
                resultKind={(displayResultClass.replace('result-', '') || '') as
                  | ''
                  | 'win'
                  | 'lose'
                  | 'draw'}
                cycling={displayCycling}
                {selectedHand}
                {busy}
                onSelectHand={setHand}
                {kpiTvl}
                {kpiVrf}
              />
              <div class="status-line {statusKind}">
                <span class="status-dot"></span>
                {#if statusHtml}
                  <span class="status-text">{@html statusText}</span>
                {:else}
                  <span class="status-text">{statusText || i18n.t('janken.ready')}</span>
                {/if}
              </div>
            </div>
          </div>

          <!-- RIGHT: bet slip -->
          <aside class="slip-panel">
            <!-- Session strip -->
            <div class="session-row">
              <span class="badge {sessionBadge.cls}">{sessionBadge.text}</span>
              <span class="credits">
                {Number(formatEther(sessionCredits)).toFixed(4)} ETH
              </span>
              <span class="exp">⏱ {sessionRemainingLabel}</span>
              <div class="actions">
                {#if !sessionActive}
                  <button class="s-btn primary" onclick={openSessionModal}>
                    {i18n.t('janken.session.start')}
                  </button>
                {:else}
                  <button class="s-btn" onclick={topUp}>
                    {i18n.t('janken.session.topup')}
                  </button>
                {/if}
                {#if sessionActive || sessionCredits > 0n}
                  <button class="s-btn warn" onclick={endSession} aria-label="end session">⨯</button>
                {/if}
              </div>
            </div>

            <!-- Hand toggle (Long/Short/Swap equivalent) -->
            <div class="hand-toggle" role="tablist">
              <button
                class="ht-btn rock"
                class:active={selectedHand === 0}
                disabled={busy}
                onclick={() => setHand(0)}
              >
                <span class="ht-cap">✊</span>
                <span class="ht-tab">{i18n.t('janken.rock')}</span>
              </button>
              <button
                class="ht-btn paper"
                class:active={selectedHand === 1}
                disabled={busy}
                onclick={() => setHand(1)}
              >
                <span class="ht-cap">✋</span>
                <span class="ht-tab">{i18n.t('janken.paper')}</span>
              </button>
              <button
                class="ht-btn sci"
                class:active={selectedHand === 2}
                disabled={busy}
                onclick={() => setHand(2)}
              >
                <span class="ht-cap">✌️</span>
                <span class="ht-tab">{i18n.t('janken.scissors')}</span>
              </button>
            </div>

            <!-- Bet input -->
            <div class="slip-field">
              <div class="slip-field-head">
                <span>{i18n.t('janken.betAmount')}</span>
                <span class="slip-field-tag">ETH</span>
              </div>
              <div class="slip-input">
                <input type="number" min="0.001" step="0.001" bind:value={betEth} />
                <span class="unit">ETH</span>
              </div>
              <div class="preset-row">
                {#each ['0.001', '0.01', '0.05', '0.1', '0.5'] as p}
                  <button class="preset" onclick={() => preset(p)}>{p}</button>
                {/each}
              </div>
            </div>

            <!-- Multiplier distribution -->
            <div class="mult-grid">
              {#each MULTS as { m, p }}
                <div class="mult">
                  <span class="mm">{m}×</span>
                  <span class="mp">{p}%</span>
                </div>
              {/each}
            </div>

            <!-- Play CTA -->
            <button
              class="big-cta"
              disabled={playDisabled}
              onclick={play}
            >
              {#if !wallet.account}
                {i18n.t('common.connect')}
              {:else if !sessionActive}
                {i18n.t('janken.session.start')}
              {:else if selectedHand === null}
                {i18n.t('janken.ready')}
              {:else}
                {i18n.t('janken.playBtn')}
              {/if}
            </button>

            <!-- Execution details -->
            <div class="exec">
              <div class="exec-row">
                <span class="k">{i18n.t('janken.slip.payout')}</span>
                <span class="v">{fmt(expectedPayoutOnWin)} ETH</span>
              </div>
              <div class="exec-row">
                <span class="k">House edge</span>
                <span class="v">7.00%</span>
              </div>
              <div class="exec-row">
                <span class="k">{i18n.t('janken.slip.ev')}</span>
                <span class="v" class:neg={evNum < 0}>{fmt(evNum)} ETH</span>
              </div>
              <div class="exec-row">
                <span class="k">{i18n.t('janken.session.key')}</span>
                <span class="v mono" title={sessionKeyFull}>{sessionKeyAddr}</span>
              </div>
              <div class="exec-row">
                <span class="k">{i18n.t('janken.session.gas')}</span>
                <span class="v">{Number(formatEther(sessionGas)).toFixed(4)} ETH</span>
              </div>
            </div>
          </aside>
        </section>
      {:else if activeView === 'lp'}
        <section class="lp-grid">
          <div class="lp-card">
            <header class="card-head">
              <h3>{i18n.t('janken.yourPos')}</h3>
              <span class="card-tag">{posPct}</span>
            </header>
            <div class="kpis-3">
              <div class="kpi-item">
                <span class="m-k">{i18n.t('janken.myShares')}</span>
                <span class="m-v">{posShares}</span>
              </div>
              <div class="kpi-item">
                <span class="m-k">{i18n.t('janken.myClaim')}</span>
                <span class="m-v">{posClaimEth}<span class="m-u">ETH</span></span>
              </div>
              <div class="kpi-item">
                <span class="m-k">{i18n.t('janken.poolShare')}</span>
                <span class="m-v">{posPct}</span>
              </div>
            </div>

            <div class="pool-bar-wrap">
              <div class="pool-bar-head">
                <span>{i18n.t('janken.poolBreakdown')}</span>
                <span>{poolTotal} ETH</span>
              </div>
              <div class="pool-bar">
                <div class="mine" style="width: {poolBarMine}%"></div>
                <div class="rest" style="width: {100 - poolBarMine}%"></div>
              </div>
              <div class="pool-bar-foot">
                <span>you {poolYou} ETH</span>
                <span>others {poolOthers} ETH</span>
              </div>
            </div>

            <div class="defi-note">{@html i18n.t('janken.defiNote')}</div>
          </div>

          <aside class="lp-card slim">
            <header class="card-head">
              <h3>{i18n.t('janken.manage')}</h3>
            </header>

            <div class="lp-form">
              <div class="lp-section">
                <span class="lp-hint">{i18n.t('janken.depositLabel')}</span>
                <div class="slip-input">
                  <input type="number" min="0.001" step="0.001" bind:value={lpAmount} />
                  <span class="unit">ETH</span>
                </div>
                <span class="lp-hint">{depositPreview}</span>
                <button class="big-cta success" onclick={lpDeposit}>
                  {i18n.t('janken.lpDeposit')}
                </button>
              </div>

              <div class="lp-divider"></div>

              <div class="lp-section">
                <span class="lp-hint">{i18n.t('janken.withdrawLabel')}</span>
                <div class="slip-input">
                  <input
                    type="number"
                    min="0"
                    step="1"
                    placeholder="shares"
                    bind:value={lpWithdrawShares}
                  />
                  <button class="preset inline" onclick={lpMax}>{i18n.t('janken.max')}</button>
                </div>
                <span class="lp-hint">{withdrawPreview}</span>
                <button class="big-cta danger" onclick={lpWithdraw}>
                  {i18n.t('janken.lpWithdraw')}
                </button>
              </div>
            </div>
          </aside>
        </section>
      {:else}
        <section class="lb-empty">
          <div class="lb-card">
            <span class="card-tag">{i18n.t('janken.leaderboard.tag')}</span>
            <h3>{i18n.t('janken.leaderboard.title')}</h3>
            <p>{i18n.t('janken.leaderboard.soon')}</p>
            <table class="pos-table">
              <thead>
                <tr>
                  <th>{i18n.t('janken.leaderboard.col.rank')}</th>
                  <th>{i18n.t('janken.leaderboard.col.player')}</th>
                  <th>{i18n.t('janken.leaderboard.col.pnl')}</th>
                  <th>{i18n.t('janken.leaderboard.col.rounds')}</th>
                  <th>{i18n.t('janken.leaderboard.col.best')}</th>
                </tr>
              </thead>
              <tbody>
                <tr class="empty"><td colspan="5">indexer offline · check back soon</td></tr>
              </tbody>
            </table>
          </div>
        </section>
      {/if}

      <!-- Bottom positions panel — recent rounds -->
      <section class="positions-panel">
        <header class="pos-head">
          <div class="pos-tabs">
            <button class="pt-btn active">
              {i18n.t('janken.recent')} <span class="pt-count">{history.length}</span>
            </button>
          </div>
          <div class="pos-raw">
            <span class="raw-label">{i18n.t('common.raw')}</span>
            <code>{randHex.slice(0, 18)}{randHex.length > 18 ? '…' : ''}</code>
          </div>
        </header>
        <div class="pos-table-wrap">
          <table class="pos-table">
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
                        class="outcome-pill {r.outcome === 2
                          ? 'win'
                          : r.outcome === 1
                            ? 'draw'
                            : 'lose'}"
                      >
                        {r.outcome === 2 ? `WIN ${r.mult}×` : r.outcome === 1 ? 'DRAW' : 'LOSE'}
                      </span>
                    </td>
                    <td>
                      {HAND_NAMES[r.pHand]}
                      <span class="muted">vs</span>
                      {HAND_NAMES[r.hHand]}
                    </td>
                    <td>{formatEther(r.bet)}</td>
                    <td
                      class:pos={r.outcome === 2}
                      class:neg={r.outcome === 0}
                    >
                      {r.outcome === 2
                        ? `+${formatEther(r.payout)}`
                        : r.outcome === 1
                          ? '±0'
                          : `−${formatEther(r.bet)}`}
                    </td>
                    <td><span class="hash mono">{hash.slice(0, 10)}…</span></td>
                  </tr>
                {/each}
              {/if}
            </tbody>
          </table>
        </div>
      </section>
    </main>
  </div>
</div>

{#if modalOpen}
  <div
    class="modal-backdrop"
    onclick={() => (modalOpen = false)}
    onkeydown={(e) => e.key === 'Escape' && (modalOpen = false)}
    role="presentation"
  >
    <div class="modal" onclick={(e) => e.stopPropagation()} role="dialog" tabindex="-1">
      <h3>{i18n.t('janken.modal.title')}</h3>
      <p class="sub">{@html i18n.t('janken.modal.sub')}</p>

      <div class="modal-field">
        <label for="m-deposit">{i18n.t('janken.modal.deposit')}</label>
        <div class="slip-input">
          <input id="m-deposit" type="number" min="0.001" step="0.01" bind:value={modalDeposit} />
          <span class="unit">ETH</span>
        </div>
      </div>

      <div class="modal-field">
        <label for="m-gas">{i18n.t('janken.modal.gas')}</label>
        <div class="slip-input">
          <input id="m-gas" type="number" min="0.005" step="0.005" bind:value={modalGas} />
          <span class="unit">ETH</span>
        </div>
        <span class="hint">{i18n.t('janken.modal.gasHint')}</span>
      </div>

      <div class="modal-field">
        <label for="m-hours">{i18n.t('janken.modal.duration')}</label>
        <div class="slip-input">
          <input id="m-hours" type="number" min="1" max="24" step="1" bind:value={modalHours} />
          <span class="unit">hours</span>
        </div>
      </div>

      <div class="modal-field">
        <label for="m-key">{i18n.t('janken.modal.key')}</label>
        <span class="hint mono" id="m-key">{sessionKeyFull}</span>
      </div>

      <div class="modal-actions">
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
  /* ═══════════════════════════════════════════════════════════════
     GMX-inspired tokens, scoped to Jankenman page.
     ═══════════════════════════════════════════════════════════════ */
  .gmx-shell {
    /* Re-use the landing's tokamak.css tokens — keep visual continuity
       across pages. Only the layout shape (sidebar + topbar + slip)
       comes from the GMX skeleton; colors, type, radii match landing. */
    --gmx-bg: var(--cream);
    --gmx-surface: var(--paper);
    --gmx-card: var(--paper-2);
    --gmx-card-2: #243049;
    --gmx-line: var(--line-1);
    --gmx-line-2: var(--line-2);
    --gmx-line-3: var(--line-3);
    --gmx-primary: var(--tk-blue);
    --gmx-primary-hover: #3d85f0;
    --gmx-primary-soft: var(--glow-soft);
    --gmx-primary-glow: var(--glow);
    --gmx-text: var(--ink);
    --gmx-text-2: var(--ink-soft);
    --gmx-text-3: var(--ink-faint);
    --gmx-success: var(--success);
    --gmx-success-soft: rgba(0, 204, 102, 0.14);
    --gmx-error: var(--error);
    --gmx-error-soft: rgba(255, 77, 94, 0.14);
    --gmx-warn: var(--warn);
    --gmx-warn-soft: rgba(255, 200, 87, 0.14);
    --r-sm: var(--radius-sm);
    --r-md: var(--radius-md);
    --r-lg: var(--radius-lg);
    --r-xl: var(--radius-xl);

    display: grid;
    grid-template-columns: 220px minmax(0, 1fr);
    min-height: 100vh;
    background: var(--gmx-bg);
    color: var(--gmx-text);
    font-family: var(--font-sans);
    letter-spacing: -0.005em;
  }

  :global(body) {
    background: var(--cream);
    padding: 0;
    font-family: var(--font-sans);
  }

  /* ─── Sidebar ──────────────────────────────────────────────── */
  .sb {
    background: var(--gmx-surface);
    border-right: 1px solid var(--gmx-line);
    display: flex;
    flex-direction: column;
    padding: 14px 12px 12px;
    gap: 4px;
    position: sticky;
    top: 0;
    height: 100vh;
  }
  .sb-brand {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 10px 18px;
    text-decoration: none;
    color: var(--gmx-text);
  }
  .sb-brand:hover {
    color: var(--gmx-text);
    text-decoration: none;
  }
  .sb-mark {
    width: 26px;
    height: 26px;
    display: grid;
    place-items: center;
  }
  .sb-mark :global(svg) {
    width: 100%;
    height: 100%;
  }
  .sb-name {
    font-weight: 700;
    font-size: 15px;
    letter-spacing: -0.02em;
  }

  .sb-nav {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .sb-item {
    appearance: none;
    border: 0;
    background: transparent;
    color: var(--gmx-text-2);
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 12px;
    border-radius: var(--r-md);
    font: inherit;
    font-size: 13.5px;
    font-weight: 500;
    cursor: pointer;
    text-align: left;
    transition:
      background 0.15s ease,
      color 0.15s ease;
  }
  .sb-item:hover {
    background: rgba(255, 255, 255, 0.04);
    color: var(--gmx-text);
  }
  .sb-item.active {
    background: var(--gmx-primary-soft);
    color: var(--gmx-primary);
  }
  .sb-icon {
    width: 18px;
    height: 18px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .sb-foot {
    margin-top: auto;
    padding: 12px 4px 4px;
    border-top: 1px solid var(--gmx-line);
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .sb-back {
    color: var(--gmx-text-3);
    text-decoration: none;
    font-size: 14px;
    padding: 4px 8px;
    border-radius: var(--r-sm);
  }
  .sb-back:hover {
    color: var(--gmx-text);
    background: rgba(255, 255, 255, 0.04);
    text-decoration: none;
  }

  /* ─── Main column ──────────────────────────────────────────── */
  .gmx-main {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  /* ─── Topbar ───────────────────────────────────────────────── */
  .topbar {
    display: flex;
    align-items: center;
    gap: 28px;
    padding: 12px 24px;
    border-bottom: 1px solid var(--gmx-line);
    min-height: 64px;
    background: var(--gmx-bg);
    position: sticky;
    top: 0;
    z-index: 10;
  }
  .pair {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    background: var(--gmx-card);
    border: 1px solid var(--gmx-line);
    border-radius: var(--r-md);
    flex-shrink: 0;
  }
  .pair-name {
    font-weight: 700;
    font-size: 13.5px;
    letter-spacing: -0.01em;
  }

  .topbar-metrics {
    display: flex;
    gap: 32px;
    flex: 1;
    min-width: 0;
    overflow-x: auto;
    scrollbar-width: none;
  }
  .topbar-metrics::-webkit-scrollbar {
    display: none;
  }
  .metric {
    display: flex;
    flex-direction: column;
    gap: 2px;
    flex-shrink: 0;
  }
  .metric .m-k {
    font-size: 10.5px;
    color: var(--gmx-text-2);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-weight: 500;
  }
  .metric .m-v {
    font-size: 15px;
    font-weight: 600;
    color: var(--gmx-text);
    font-variant-numeric: tabular-nums;
    letter-spacing: -0.01em;
  }
  .metric .m-u {
    font-size: 11.5px;
    color: var(--gmx-text-2);
    font-weight: 500;
    margin-left: 4px;
  }
  .metric.vrf-metric .m-v {
    color: var(--gmx-primary);
    text-shadow: 0 0 12px var(--gmx-primary-glow);
  }

  .connect {
    appearance: none;
    background: var(--gmx-primary);
    color: white;
    border: 0;
    border-radius: var(--r-md);
    padding: 9px 18px;
    font: inherit;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    letter-spacing: -0.005em;
    flex-shrink: 0;
    transition: background 0.15s ease;
  }
  .connect:hover:not(:disabled) {
    background: var(--gmx-primary-hover);
  }
  .connect:disabled {
    opacity: 0.7;
    cursor: not-allowed;
  }

  /* ─── Content scaffold ─────────────────────────────────────── */
  .content {
    padding: 20px 24px 40px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    min-width: 0;
  }

  /* ─── Game grid (chart + slip) ─────────────────────────────── */
  .game-grid {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 380px;
    gap: 16px;
  }
  @media (max-width: 980px) {
    .game-grid {
      grid-template-columns: 1fr;
    }
  }

  .board-panel,
  .slip-panel {
    background: var(--gmx-surface);
    border: 1px solid var(--gmx-line);
    border-radius: var(--r-lg);
    padding: 16px;
  }
  .slip-panel {
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  /* ─── 3D arcade cabinet host ─────────────────────────────── */
  .cabinet-host {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  /* ─── Arcade cabinet (GMX-fied — legacy CSS, no longer rendered) ──── */
  .arcade-cabinet {
    background: linear-gradient(180deg, #0e1530 0%, #050a1c 100%);
    border: 1px solid var(--gmx-line-2);
    border-radius: var(--r-md);
    padding: 6px;
    position: relative;
  }
  .cabinet-marquee {
    background: linear-gradient(180deg, var(--tk-blue) 0%, var(--tk-blue-deep) 100%);
    border: 1px solid rgba(0, 0, 0, 0.4);
    border-radius: 8px 8px 4px 4px;
    padding: 8px 14px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
  }
  .cabinet-marquee .mt {
    font-weight: 700;
    letter-spacing: 0.32em;
    font-size: 13px;
    color: #fff;
    text-shadow:
      0 0 10px rgba(255, 255, 255, 0.6),
      0 0 18px var(--gmx-primary-glow);
  }
  .cabinet-marquee .ml {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #ffe29a;
    box-shadow:
      0 0 10px #ffe29a,
      0 0 4px #fff;
    animation: marquee-blink 1.3s infinite;
  }
  .cabinet-marquee .ml:nth-child(1) { animation-delay: 0s; }
  .cabinet-marquee .ml:nth-child(2) { animation-delay: 0.15s; }
  .cabinet-marquee .ml:nth-child(3) { animation-delay: 0.3s; }
  .cabinet-marquee .ml:nth-child(5) { animation-delay: 0.45s; }
  .cabinet-marquee .ml:nth-child(6) { animation-delay: 0.6s; }
  .cabinet-marquee .ml:nth-child(7) { animation-delay: 0.75s; }
  @keyframes marquee-blink {
    0%, 100% { opacity: 0.35; transform: scale(0.8); }
    50% { opacity: 1; transform: scale(1.15); }
  }

  .cabinet-screen {
    margin: 6px 2px 2px;
    background: radial-gradient(ellipse at center, #0d1a40 0%, #050b22 100%);
    border: 1px solid rgba(0, 0, 0, 0.6);
    border-radius: 8px;
    padding: 24px 20px 18px;
    min-height: 380px;
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

  .jk-stage {
    position: relative;
    z-index: 1;
    width: min(360px, 80vw);
    aspect-ratio: 1;
    margin: 0 auto;
  }
  .jk-pointer {
    position: absolute;
    top: -4px;
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
    border: 3px solid #000;
    box-shadow:
      0 0 0 2px rgba(0, 0, 0, 0.4),
      0 0 30px var(--gmx-primary-glow),
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
    border: 2px solid #000;
    box-shadow:
      0 0 16px rgba(143, 214, 185, 0.35),
      inset 0 0 14px rgba(0, 0, 0, 0.15);
    z-index: 2;
  }
  .jk-display {
    position: absolute;
    inset: 37%;
    border-radius: 8px;
    background: radial-gradient(circle at 50% 50%, #3a0c0c 0%, #150303 85%);
    border: 2px solid #000;
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
    font-size: clamp(48px, 9vw, 72px);
    line-height: 1;
    filter: drop-shadow(0 0 6px #ff2a2a) drop-shadow(0 0 12px #ff4040) saturate(1.4);
    transition: transform 0.08s ease;
  }
  .jk-display.cycling .jk-display-emoji {
    animation: display-flicker 0.12s infinite;
  }
  @keyframes display-flicker {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.82; }
  }
  .jk-display.result-win {
    box-shadow:
      inset 0 0 24px rgba(0, 186, 114, 0.45),
      0 0 22px rgba(0, 186, 114, 0.55);
  }
  .jk-display.result-lose {
    box-shadow:
      inset 0 0 24px rgba(255, 92, 92, 0.45),
      0 0 22px rgba(255, 92, 92, 0.55);
  }
  .jk-display.result-draw {
    box-shadow:
      inset 0 0 24px rgba(255, 200, 87, 0.45),
      0 0 22px rgba(255, 200, 87, 0.55);
  }

  .status-line {
    position: relative;
    z-index: 3;
    margin-top: 16px;
    background: #000;
    border: 1px solid rgba(0, 186, 114, 0.3);
    border-radius: 6px;
    padding: 9px 14px;
    font-size: 11.5px;
    font-weight: 600;
    color: var(--gmx-success);
    letter-spacing: 0.1em;
    text-transform: uppercase;
    text-shadow: 0 0 10px currentColor;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    min-height: 36px;
    text-align: center;
    font-family: var(--font-mono);
    font-variant-numeric: tabular-nums;
  }
  .status-line .status-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: currentColor;
    box-shadow: 0 0 10px currentColor;
    animation: dot-blink 1s infinite;
    flex-shrink: 0;
  }
  @keyframes dot-blink {
    50% { opacity: 0.25; }
  }
  .status-line.win {
    color: var(--gmx-success);
    border-color: rgba(0, 186, 114, 0.5);
  }
  .status-line.lose {
    color: var(--gmx-error);
    border-color: rgba(255, 92, 92, 0.5);
  }
  .status-line.draw {
    color: var(--gmx-warn);
    border-color: rgba(255, 200, 87, 0.5);
  }

  /* ─── Session row (slip top strip) ─────────────────────────── */
  .session-row {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 10px;
    background: var(--gmx-bg);
    border: 1px solid var(--gmx-line);
    border-radius: var(--r-md);
    font-size: 12px;
    flex-wrap: wrap;
  }
  .session-row .badge {
    padding: 3px 8px;
    border-radius: 999px;
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }
  .session-row .badge.idle {
    background: var(--gmx-warn-soft);
    color: var(--gmx-warn);
  }
  .session-row .badge.active {
    background: var(--gmx-success-soft);
    color: var(--gmx-success);
  }
  .session-row .badge.expired {
    background: var(--gmx-error-soft);
    color: var(--gmx-error);
  }
  .session-row .credits {
    font-weight: 600;
    color: var(--gmx-text);
    font-variant-numeric: tabular-nums;
  }
  .session-row .exp {
    color: var(--gmx-text-2);
    font-variant-numeric: tabular-nums;
    font-size: 11.5px;
  }
  .session-row .actions {
    margin-left: auto;
    display: flex;
    gap: 4px;
  }

  /* ─── Hand toggle (Long/Short/Swap equivalent) ─────────────── */
  .hand-toggle {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 4px;
    background: var(--gmx-bg);
    border: 1px solid var(--gmx-line);
    border-radius: var(--r-md);
    padding: 4px;
  }
  .ht-btn {
    appearance: none;
    border: 0;
    background: transparent;
    color: var(--gmx-text-2);
    padding: 9px 6px;
    border-radius: 6px;
    font: inherit;
    font-weight: 600;
    font-size: 12.5px;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    transition:
      background 0.15s ease,
      color 0.15s ease;
  }
  .ht-btn:hover:not(:disabled):not(.active) {
    color: var(--gmx-text);
    background: rgba(255, 255, 255, 0.03);
  }
  .ht-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .ht-btn.active {
    background: var(--gmx-primary);
    color: white;
  }
  .ht-btn.active.rock {
    background: #ff5c5c;
  }
  .ht-btn.active.paper {
    background: #ffc857;
    color: #1a1a1a;
  }
  .ht-btn.active.sci {
    background: var(--tk-blue);
  }
  .ht-cap {
    font-size: 16px;
    line-height: 1;
  }

  /* ─── Slip field ───────────────────────────────────────────── */
  .slip-field {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .slip-field-head {
    display: flex;
    justify-content: space-between;
    font-size: 10.5px;
    text-transform: uppercase;
    color: var(--gmx-text-2);
    letter-spacing: 0.08em;
    font-weight: 500;
  }
  .slip-field-tag {
    color: var(--gmx-text-3);
  }
  .slip-input {
    display: flex;
    align-items: center;
    background: var(--gmx-bg);
    border: 1px solid var(--gmx-line);
    border-radius: var(--r-md);
    padding: 10px 12px;
    transition: border-color 0.15s ease;
  }
  .slip-input:focus-within {
    border-color: var(--gmx-line-3);
  }
  .slip-input input {
    flex: 1;
    background: transparent;
    border: 0;
    outline: 0;
    color: var(--gmx-text);
    font: inherit;
    font-size: 17px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    letter-spacing: -0.01em;
    min-width: 0;
  }
  .slip-input .unit {
    color: var(--gmx-text-2);
    font-size: 12.5px;
    font-weight: 500;
  }
  .preset-row {
    display: flex;
    gap: 4px;
  }
  .preset {
    appearance: none;
    background: var(--gmx-card);
    border: 1px solid var(--gmx-line);
    color: var(--gmx-text-2);
    padding: 5px 10px;
    border-radius: 999px;
    font: inherit;
    font-size: 11px;
    font-weight: 500;
    cursor: pointer;
    font-variant-numeric: tabular-nums;
    transition:
      color 0.15s ease,
      border-color 0.15s ease,
      background 0.15s ease;
  }
  .preset:hover {
    color: var(--gmx-text);
    border-color: var(--gmx-line-2);
  }
  .preset.inline {
    margin-left: 4px;
  }

  /* ─── Mult grid ────────────────────────────────────────────── */
  .mult-grid {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    gap: 4px;
  }
  .mult {
    background: var(--gmx-bg);
    border: 1px solid var(--gmx-line);
    border-radius: 6px;
    padding: 7px 4px;
    text-align: center;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .mult .mm {
    color: var(--gmx-text);
    font-weight: 600;
    font-size: 12.5px;
    font-variant-numeric: tabular-nums;
  }
  .mult .mp {
    color: var(--gmx-text-3);
    font-size: 10px;
    font-variant-numeric: tabular-nums;
  }

  /* ─── Big CTA ──────────────────────────────────────────────── */
  .big-cta {
    appearance: none;
    width: 100%;
    background: var(--gmx-primary);
    color: white;
    border: 0;
    border-radius: var(--r-md);
    padding: 14px;
    font: inherit;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    letter-spacing: -0.005em;
    transition: background 0.15s ease;
  }
  .big-cta:not(:disabled):hover {
    background: var(--gmx-primary-hover);
  }
  .big-cta:disabled {
    background: var(--gmx-card);
    color: var(--gmx-text-3);
    cursor: not-allowed;
  }
  .big-cta.success {
    background: var(--gmx-success);
  }
  .big-cta.success:hover {
    background: #00d181;
  }
  .big-cta.danger {
    background: transparent;
    border: 1px solid var(--gmx-error);
    color: var(--gmx-error);
  }
  .big-cta.danger:hover {
    background: var(--gmx-error-soft);
  }

  /* ─── Execution details rows ───────────────────────────────── */
  .exec {
    border-top: 1px solid var(--gmx-line);
    padding-top: 10px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .exec-row {
    display: flex;
    justify-content: space-between;
    font-size: 12px;
    align-items: baseline;
  }
  .exec-row .k {
    color: var(--gmx-text-2);
  }
  .exec-row .v {
    color: var(--gmx-text);
    font-variant-numeric: tabular-nums;
    font-weight: 500;
  }
  .exec-row .v.neg {
    color: var(--gmx-error);
  }
  .exec-row .v.pos {
    color: var(--gmx-success);
  }
  .mono {
    font-family: var(--font-mono);
    font-feature-settings: 'tnum';
  }

  /* ─── Small button (s-btn) ─────────────────────────────────── */
  .s-btn {
    appearance: none;
    background: var(--gmx-card);
    border: 1px solid var(--gmx-line);
    color: var(--gmx-text);
    padding: 6px 12px;
    border-radius: var(--r-md);
    font: inherit;
    font-size: 11.5px;
    font-weight: 600;
    cursor: pointer;
    transition: background 0.15s ease;
  }
  .s-btn:hover:not(:disabled) {
    background: var(--gmx-card-2);
  }
  .s-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .s-btn.primary {
    background: var(--gmx-primary);
    border-color: var(--gmx-primary);
    color: white;
  }
  .s-btn.primary:hover:not(:disabled) {
    background: var(--gmx-primary-hover);
  }
  .s-btn.warn {
    background: transparent;
    border-color: var(--gmx-error);
    color: var(--gmx-error);
    width: 28px;
    padding: 6px;
  }
  .s-btn.warn:hover {
    background: var(--gmx-error-soft);
  }

  /* ─── LP grid ──────────────────────────────────────────────── */
  .lp-grid {
    display: grid;
    grid-template-columns: minmax(0, 1.2fr) 380px;
    gap: 16px;
  }
  @media (max-width: 980px) {
    .lp-grid {
      grid-template-columns: 1fr;
    }
  }
  .lp-card {
    background: var(--gmx-surface);
    border: 1px solid var(--gmx-line);
    border-radius: var(--r-lg);
    padding: 18px;
  }
  .lp-card.slim {
    padding: 18px;
  }
  .card-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 14px;
  }
  .card-head h3 {
    font-size: 14px;
    font-weight: 700;
    letter-spacing: -0.01em;
    color: var(--gmx-text);
  }
  .card-tag {
    font-size: 11px;
    color: var(--gmx-text-2);
    font-variant-numeric: tabular-nums;
    font-weight: 500;
  }
  .kpis-3 {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
    gap: 10px;
    margin-bottom: 16px;
  }
  .kpi-item {
    display: flex;
    flex-direction: column;
    gap: 4px;
    background: var(--gmx-bg);
    border: 1px solid var(--gmx-line);
    border-radius: var(--r-md);
    padding: 10px 12px;
  }
  .kpi-item .m-k {
    font-size: 10px;
    color: var(--gmx-text-2);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-weight: 500;
  }
  .kpi-item .m-v {
    font-size: 15px;
    font-weight: 600;
    color: var(--gmx-text);
    font-variant-numeric: tabular-nums;
    letter-spacing: -0.01em;
  }
  .kpi-item .m-u {
    font-size: 11.5px;
    color: var(--gmx-text-2);
    margin-left: 4px;
    font-weight: 500;
  }

  .pool-bar-wrap {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .pool-bar-head,
  .pool-bar-foot {
    display: flex;
    justify-content: space-between;
    font-size: 11px;
    color: var(--gmx-text-2);
    font-variant-numeric: tabular-nums;
  }
  .pool-bar-head {
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }
  .pool-bar {
    height: 8px;
    border-radius: 999px;
    background: var(--gmx-card);
    overflow: hidden;
    display: flex;
  }
  .pool-bar .mine {
    background: var(--gmx-primary);
  }
  .pool-bar .rest {
    background: var(--gmx-card-2);
  }

  .defi-note {
    font-size: 12px;
    color: var(--gmx-text-2);
    line-height: 1.6;
    padding: 10px 12px;
    border-left: 2px solid var(--gmx-primary);
    background: var(--gmx-primary-soft);
    border-radius: 0 var(--r-md) var(--r-md) 0;
    margin-top: 14px;
  }
  .defi-note :global(b) {
    color: var(--gmx-text);
  }
  .defi-note :global(code) {
    background: rgba(42, 114, 229, 0.18);
    color: var(--gmx-text);
    padding: 1px 6px;
    border-radius: var(--r-sm);
    font-size: 0.92em;
    font-family: inherit;
    font-variant-numeric: tabular-nums;
  }

  .lp-form {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .lp-section {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .lp-hint {
    font-size: 11px;
    color: var(--gmx-text-2);
  }
  .lp-divider {
    height: 1px;
    background: var(--gmx-line);
  }

  /* ─── Leaderboard placeholder ──────────────────────────────── */
  .lb-empty {
    display: flex;
  }
  .lb-card {
    flex: 1;
    background: var(--gmx-surface);
    border: 1px solid var(--gmx-line);
    border-radius: var(--r-lg);
    padding: 24px;
  }
  .lb-card h3 {
    font-size: 18px;
    font-weight: 700;
    letter-spacing: -0.02em;
    margin: 6px 0 6px;
  }
  .lb-card p {
    font-size: 13px;
    color: var(--gmx-text-2);
    line-height: 1.55;
    max-width: 60ch;
    margin-bottom: 18px;
  }

  /* ─── Bottom positions panel ───────────────────────────────── */
  .positions-panel {
    background: var(--gmx-surface);
    border: 1px solid var(--gmx-line);
    border-radius: var(--r-lg);
    overflow: hidden;
  }
  .pos-head {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0 16px;
    border-bottom: 1px solid var(--gmx-line);
    flex-wrap: wrap;
    gap: 10px;
  }
  .pos-tabs {
    display: flex;
  }
  .pt-btn {
    appearance: none;
    border: 0;
    background: transparent;
    color: var(--gmx-text-2);
    padding: 12px 0;
    margin-right: 18px;
    font: inherit;
    font-size: 12.5px;
    font-weight: 500;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    border-bottom: 2px solid transparent;
    margin-bottom: -1px;
    transition:
      color 0.15s ease,
      border-color 0.15s ease;
  }
  .pt-btn:hover {
    color: var(--gmx-text);
  }
  .pt-btn.active {
    color: var(--gmx-text);
    border-bottom-color: var(--gmx-primary);
  }
  .pt-count {
    background: var(--gmx-card);
    color: var(--gmx-text-2);
    font-size: 10.5px;
    padding: 1px 7px;
    border-radius: 999px;
    font-variant-numeric: tabular-nums;
  }
  .pos-raw {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 11px;
    color: var(--gmx-text-3);
    padding: 8px 0;
  }
  .pos-raw .raw-label {
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }
  .pos-raw code {
    color: var(--gmx-text-2);
    background: var(--gmx-card);
    padding: 3px 7px;
    border-radius: var(--r-sm);
    font-size: 10.5px;
    font-family: var(--font-mono);
    font-variant-numeric: tabular-nums;
  }
  .pos-table-wrap {
    overflow-x: auto;
  }
  .pos-table {
    width: 100%;
    border-collapse: collapse;
    font-variant-numeric: tabular-nums;
  }
  .pos-table th {
    text-align: left;
    padding: 10px 16px;
    font-size: 10.5px;
    color: var(--gmx-text-3);
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    background: var(--gmx-bg);
    border-bottom: 1px solid var(--gmx-line);
  }
  .pos-table td {
    padding: 12px 16px;
    border-top: 1px solid var(--gmx-line);
    font-size: 13px;
    color: var(--gmx-text);
  }
  .pos-table tr.empty td {
    text-align: center;
    color: var(--gmx-text-3);
    padding: 36px 16px;
    font-size: 12.5px;
  }
  .pos-table .muted {
    color: var(--gmx-text-3);
    margin: 0 4px;
    font-size: 11px;
  }
  .pos-table .pos {
    color: var(--gmx-success);
    font-weight: 600;
  }
  .pos-table .neg {
    color: var(--gmx-error);
    font-weight: 600;
  }
  .pos-table .hash {
    color: var(--gmx-primary);
    font-size: 11.5px;
  }
  .outcome-pill {
    display: inline-block;
    padding: 3px 8px;
    border-radius: var(--r-sm);
    font-size: 10.5px;
    font-weight: 700;
    letter-spacing: 0.06em;
    line-height: 1.4;
  }
  .outcome-pill.win {
    background: var(--gmx-success-soft);
    color: var(--gmx-success);
  }
  .outcome-pill.draw {
    background: var(--gmx-warn-soft);
    color: var(--gmx-warn);
  }
  .outcome-pill.lose {
    background: var(--gmx-error-soft);
    color: var(--gmx-error);
  }

  /* ─── Modal ────────────────────────────────────────────────── */
  .modal-backdrop {
    /* Modal renders outside .gmx-shell, so re-map the GMX tokens here
       — otherwise the modal/inputs lose their background and borders. */
    --gmx-bg: var(--cream);
    --gmx-surface: var(--paper);
    --gmx-card: var(--paper-2);
    --gmx-line: var(--line-1);
    --gmx-line-2: var(--line-2);
    --gmx-line-3: var(--line-3);
    --gmx-text: var(--ink);
    --gmx-text-2: var(--ink-soft);
    --gmx-text-3: var(--ink-faint);
    --gmx-primary: var(--tk-blue);
    --r-md: var(--radius-md);
    --r-xl: var(--radius-xl);

    position: fixed;
    inset: 0;
    background: rgba(5, 8, 16, 0.7);
    backdrop-filter: blur(4px);
    display: grid;
    place-items: center;
    padding: 20px;
    z-index: 100;
    color: var(--gmx-text);
    font-family: var(--font-sans);
  }
  .modal {
    background: var(--gmx-surface);
    border: 1px solid var(--gmx-line-2);
    border-radius: var(--r-xl);
    padding: 24px;
    max-width: 440px;
    width: 100%;
    box-shadow: 0 30px 80px rgba(0, 0, 0, 0.6);
  }
  .modal h3 {
    font-size: 18px;
    font-weight: 700;
    letter-spacing: -0.02em;
    margin-bottom: 6px;
  }
  .modal .sub {
    font-size: 12.5px;
    color: var(--gmx-text-2);
    line-height: 1.55;
    margin-bottom: 18px;
  }
  .modal-field {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-bottom: 12px;
  }
  .modal-field label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--gmx-text-2);
    font-weight: 500;
  }
  .modal .hint {
    font-size: 11px;
    color: var(--gmx-text-3);
    font-family: inherit;
  }
  .modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 18px;
  }

  /* ─── Mobile collapse ──────────────────────────────────────── */
  @media (max-width: 720px) {
    .gmx-shell {
      grid-template-columns: 1fr;
    }
    .sb {
      position: static;
      height: auto;
      flex-direction: row;
      align-items: center;
      padding: 8px 12px;
      flex-wrap: wrap;
    }
    .sb-brand {
      padding: 4px 8px 4px 0;
    }
    .sb-nav {
      flex-direction: row;
      flex: 1;
    }
    .sb-item {
      padding: 8px 10px;
    }
    .sb-item span:not(.sb-icon) {
      display: none;
    }
    .sb-foot {
      margin: 0;
      padding: 0;
      border: 0;
    }
    .topbar {
      padding: 12px 16px;
      gap: 16px;
      flex-wrap: wrap;
    }
    .content {
      padding: 16px 12px 32px;
    }
  }
</style>
