<script lang="ts">
  import { i18n } from '$lib/i18n.svelte';
  import Topbar from '$lib/components/Topbar.svelte';
  import { jankenMascot, type Mascot } from '$lib/mascots';

  type Game = {
    href: string;
    cls: string;
    name: string;
    pin: string;
    badge: string;
    meta: string;
    tags: string[];
    descKey: string;
    mascot: Mascot;
  };
  type Soon = { cls: string; name: string; meta: string; desc: string; tags: string[] };
  type Filter = { key: string; label: string; test: (g: { tags?: string[] }) => boolean };

  const GAMES: Game[] = [
    {
      href: '/jankenman/',
      cls: 'janken',
      name: 'Jankenman',
      pin: 'Featured',
      badge: 'DeFi',
      meta: 'RPS · LP pool · session keys',
      tags: ['featured', 'vrf', 'defi', 'session'],
      descKey: 'games.janken.desc',
      mascot: jankenMascot
    }
  ];

  const SOON: Soon[] = [
    {
      cls: 'mint-soon',
      name: 'Bracket Brawl',
      meta: 'tournament · vrf',
      desc: '단일 VRF 호출로 64인 토너먼트 대진을 결정.',
      tags: ['soon']
    },
    {
      cls: 'sky-soon',
      name: 'L2 Karts',
      meta: 'race · vrf',
      desc: '랜덤 트랙 + 랜덤 부스트, 한 라운드 한 결과.',
      tags: ['soon']
    },
    {
      cls: 'coral-soon',
      name: 'Mystery Box',
      meta: 'loot · vrf',
      desc: '균등 분포 검증 가능한 가챠. 풀이 100% 온체인.',
      tags: ['soon']
    },
    {
      cls: 'lavender-soon',
      name: 'Word Wager',
      meta: 'puzzle · vrf',
      desc: 'VRF로 매일 매치 시드. 같은 시드 → 같은 게임판.',
      tags: ['soon']
    }
  ];

  const FILTERS: Filter[] = [
    { key: 'all', label: 'All', test: () => true },
    { key: 'featured', label: 'Featured', test: (g) => !!g.tags?.includes('featured') },
    { key: 'defi', label: 'DeFi', test: (g) => !!g.tags?.includes('defi') },
    { key: 'session', label: 'Session keys', test: (g) => !!g.tags?.includes('session') },
    { key: 'soon', label: 'Coming soon', test: (g) => !!g.tags?.includes('soon') }
  ];

  let activeFilter = $state('all');

  function counts(key: string): number {
    const f = FILTERS.find((x) => x.key === key)!;
    const all = key === 'soon' ? SOON : key === 'all' ? [...GAMES, ...SOON] : GAMES;
    return all.filter(f.test).length;
  }

  const liveCards = $derived.by(() => {
    if (activeFilter === 'soon') return [];
    const f = FILTERS.find((x) => x.key === activeFilter)!;
    return GAMES.filter(f.test);
  });
  const soonCards = $derived.by(() =>
    activeFilter === 'all' || activeFilter === 'soon' ? SOON : []
  );
  const total = $derived(liveCards.length + soonCards.length);
</script>

<svelte:head>
  <title>{i18n.t('hub.title')}</title>
</svelte:head>

<div id="topbar">
  <Topbar hubHref="/" />
</div>

<main>
  <header class="games-header">
    <a class="crumb" href="/">{i18n.t('common.back.landing')}</a>
    <span class="eyebrow">
      <span class="live-dot"></span>
      <span>{i18n.t('hub.eyebrow')}</span>
    </span>
    <h1>{i18n.t('hub.h1')}</h1>
    <p>{@html i18n.t('hub.lede')}</p>
  </header>

  <section class="featured-banner">
    <div>
      <span class="pin">★ Featured · DeFi</span>
      <h2>Jankenman</h2>
      <p>
        가위바위보 + 룰렛 + LP 풀. 단일 VRF 호출로 상대 손과 배율이 결정되고, AA 세션키로
        라운드마다 지갑 서명 없이 즉시 플레이됩니다.
      </p>
      <div class="ctas">
        <a class="btn-primary" href="/jankenman/">Play now <span aria-hidden="true">→</span></a>
        <a
          class="btn-ghost"
          href="https://enshrined-vrf-docs.vercel.app/"
          target="_blank"
          rel="noopener">How it works</a
        >
      </div>
    </div>
    <div class="visual" aria-hidden="true">{@html jankenMascot({ size: 130 })}</div>
  </section>

  <div class="filter-bar">
    <span class="label">Filter</span>
    {#each FILTERS as f (f.key)}
      <button
        type="button"
        class="chip"
        class:active={activeFilter === f.key}
        onclick={() => (activeFilter = f.key)}
      >
        {f.label} <span class="count">{counts(f.key)}</span>
      </button>
    {/each}
  </div>

  <section class="grid-section">
    <div class="grid-head">
      <h2>{i18n.t('hub.allGames')}</h2>
      <span class="stat">{total} titles</span>
    </div>
    <div class="arcade-grid">
      {#each liveCards as g (g.cls)}
        <a class="gcard {g.cls}" href={g.href}>
          <div class="art">
            <span class="pin">{g.pin}</span>
            {@html g.mascot({ size: 110 })}
          </div>
          <div class="body">
            <h3>{g.name} <span class="badge">{g.badge}</span></h3>
            <div class="meta">{g.meta}</div>
            <div class="desc">{i18n.t(g.descKey)}</div>
            <span class="go">{i18n.t('common.playnow')}</span>
          </div>
        </a>
      {/each}
      {#each soonCards as s (s.cls)}
        <div class="gcard soon {s.cls}">
          <div class="art">
            <span class="pin">Soon</span>
          </div>
          <div class="body">
            <h3>{s.name} <span class="badge">soon</span></h3>
            <div class="meta">{s.meta}</div>
            <div class="desc">{s.desc}</div>
            <span class="go">in development</span>
          </div>
        </div>
      {/each}
    </div>
  </section>

  <footer class="site-footer">
    Backed by Tokamak Network · Tokamak Arcade — an Enshrined VRF demo
  </footer>
</main>

<style>
  body {
    padding: 16px 0 0;
    background:
      radial-gradient(900px 480px at 90% -10%, rgba(42, 114, 229, 0.07), transparent 70%),
      radial-gradient(700px 460px at -10% 25%, rgba(111, 168, 255, 0.05), transparent 70%),
      var(--cream);
    background-attachment: fixed;
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
  main {
    padding: 0 32px;
  }

  .games-header {
    max-width: 1280px;
    margin: 28px auto 32px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .games-header .crumb {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-family: var(--font-sans);
    font-size: 11.5px;
    font-weight: 700;
    color: var(--ink-soft);
    text-decoration: none;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    transition: color 0.15s ease;
    align-self: flex-start;
  }
  .games-header .crumb:hover {
    color: var(--tk-blue);
    text-decoration: none;
  }
  .games-header .eyebrow {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    padding: 6px 12px;
    background: rgba(42, 114, 229, 0.06);
    border: 1px solid rgba(42, 114, 229, 0.3);
    border-radius: 100px;
    font-family: var(--font-sans);
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--tk-blue);
    align-self: flex-start;
  }
  .games-header .eyebrow .live-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--tk-blue);
    box-shadow: 0 0 0 4px var(--glow);
    animation: tokamak-pulse 2.4s ease-in-out infinite;
  }
  .games-header h1 {
    font-family: var(--font-sans);
    font-weight: 700;
    font-size: clamp(36px, 5.6vw, 64px);
    letter-spacing: -0.025em;
    line-height: 1;
    max-width: 18ch;
  }
  .games-header p {
    font-family: var(--font-sans);
    color: var(--ink-soft);
    font-size: 16px;
    font-weight: 400;
    line-height: 1.6;
    max-width: 64ch;
  }

  .featured-banner {
    max-width: 1280px;
    margin: 0 auto 56px;
    border-radius: var(--radius-xl);
    border: 1px solid var(--line-1);
    padding: 44px 48px;
    background:
      radial-gradient(640px 360px at 90% 100%, rgba(42, 114, 229, 0.2), transparent 65%),
      linear-gradient(160deg, #131927 0%, #0b0f17 100%);
    display: grid;
    grid-template-columns: minmax(0, 1.4fr) 200px;
    gap: 32px;
    align-items: center;
    position: relative;
    overflow: hidden;
  }
  .featured-banner::after {
    content: '';
    position: absolute;
    inset: 0;
    background-image:
      linear-gradient(var(--line-1) 1px, transparent 1px),
      linear-gradient(90deg, var(--line-1) 1px, transparent 1px);
    background-size: 48px 48px;
    mask-image: radial-gradient(circle at 80% 80%, #000 30%, transparent 75%);
    pointer-events: none;
    opacity: 0.4;
  }
  .featured-banner > * {
    position: relative;
    z-index: 1;
  }
  .featured-banner .pin {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 4px 10px;
    border-radius: var(--radius-sm);
    background: rgba(42, 114, 229, 0.12);
    border: 1px solid rgba(42, 114, 229, 0.3);
    font-family: var(--font-mono);
    font-size: 10.5px;
    font-weight: 700;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--tk-blue);
    margin-bottom: 18px;
  }
  .featured-banner h2 {
    font-size: clamp(28px, 3.6vw, 40px);
    font-weight: 700;
    color: var(--ink);
    margin-bottom: 10px;
  }
  .featured-banner p {
    color: var(--ink-soft);
    font-size: 14.5px;
    max-width: 56ch;
    margin-bottom: 22px;
  }
  .featured-banner .ctas {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
  }
  .btn-primary,
  .btn-ghost {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 12px 22px;
    border-radius: var(--radius-md);
    font-family: var(--font-sans);
    font-weight: 700;
    font-size: 13.5px;
    letter-spacing: 0.01em;
    text-decoration: none;
    transition:
      background 0.15s ease,
      border-color 0.15s ease,
      box-shadow 0.15s ease,
      transform 0.12s ease;
  }
  .btn-primary {
    background: var(--tk-blue);
    color: var(--tk-blue-ink);
    border: 1px solid var(--tk-blue);
  }
  .btn-primary:hover {
    background: var(--tk-blue-deep);
    border-color: var(--tk-blue-deep);
    color: var(--tk-blue-ink);
    text-decoration: none;
    box-shadow: 0 0 0 5px var(--glow-soft);
  }
  .btn-ghost {
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid var(--line-2);
    color: var(--ink);
  }
  .btn-ghost:hover {
    background: rgba(255, 255, 255, 0.08);
    border-color: var(--line-3);
    color: var(--ink);
    text-decoration: none;
  }
  .featured-banner .visual {
    aspect-ratio: 1 / 1;
    border-radius: var(--radius-lg);
    background:
      radial-gradient(circle at 30% 30%, rgba(255, 255, 255, 0.18), transparent 55%),
      linear-gradient(180deg, var(--tk-blue) 0%, var(--tk-blue-deep) 100%);
    border: 1px solid rgba(42, 114, 229, 0.4);
    display: grid;
    place-items: center;
    transform: rotate(-3deg);
    box-shadow:
      0 24px 48px rgba(0, 0, 0, 0.4),
      0 0 40px rgba(42, 114, 229, 0.18);
  }
  .featured-banner .visual :global(svg) {
    transform: scale(1.4);
    filter: drop-shadow(0 8px 16px rgba(0, 0, 0, 0.4));
  }

  @media (max-width: 820px) {
    .featured-banner {
      grid-template-columns: 1fr;
      padding: 32px 24px;
    }
    .featured-banner .visual {
      max-width: 200px;
      justify-self: start;
    }
  }

  .filter-bar {
    max-width: 1280px;
    margin: 0 auto 24px;
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
    align-items: center;
  }
  .filter-bar .label {
    font-family: var(--font-mono);
    font-size: 10.5px;
    font-weight: 600;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--ink-faint);
    margin-right: 8px;
  }
  .chip {
    appearance: none;
    cursor: pointer;
    padding: 9px 14px;
    border-radius: 100px;
    border: 1px solid var(--line-1);
    background: var(--paper);
    color: var(--ink-soft);
    font-family: var(--font-sans);
    font-weight: 600;
    font-size: 12.5px;
    letter-spacing: 0.01em;
    display: inline-flex;
    align-items: center;
    gap: 7px;
    transition:
      background 0.15s ease,
      color 0.15s ease,
      border-color 0.15s ease;
  }
  .chip:hover {
    background: var(--paper-2);
    color: var(--ink);
    border-color: var(--line-2);
  }
  .chip.active {
    background: var(--tk-blue);
    color: var(--tk-blue-ink);
    border-color: var(--tk-blue);
  }
  .chip .count {
    font-family: var(--font-mono);
    font-size: 10.5px;
    font-weight: 600;
    opacity: 0.65;
  }

  .grid-section {
    max-width: 1280px;
    margin: 0 auto 64px;
  }
  .grid-head {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    margin-bottom: 18px;
    gap: 12px;
  }
  .grid-head h2 {
    font-size: 22px;
    font-weight: 700;
    letter-spacing: -0.02em;
    color: var(--ink);
  }
  .grid-head .stat {
    font-family: var(--font-mono);
    font-size: 11px;
    color: var(--ink-faint);
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  .arcade-grid {
    display: grid;
    gap: 16px;
    grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
  }
  .gcard {
    position: relative;
    background: var(--paper);
    color: var(--ink);
    border: 1px solid var(--line-1);
    border-radius: var(--radius-lg);
    overflow: hidden;
    text-decoration: none;
    display: flex;
    flex-direction: column;
    transition:
      background 0.18s ease,
      border-color 0.18s ease,
      transform 0.18s ease;
  }
  .gcard:hover {
    background: var(--paper-2);
    border-color: var(--line-2);
    transform: translateY(-3px);
    color: var(--ink);
    text-decoration: none;
  }
  .gcard .art {
    aspect-ratio: 16 / 11;
    display: grid;
    place-items: center;
    background:
      linear-gradient(180deg, rgba(0, 0, 0, 0) 50%, rgba(0, 0, 0, 0.3) 100%),
      var(--accent);
    position: relative;
    overflow: hidden;
    border-bottom: 1px solid rgba(0, 0, 0, 0.2);
  }
  .gcard .art::after {
    content: '';
    position: absolute;
    inset: 0;
    background: radial-gradient(circle at 75% 25%, rgba(255, 255, 255, 0.2), transparent 60%);
    pointer-events: none;
  }
  .gcard .art :global(svg) {
    position: relative;
    z-index: 1;
    transform: scale(1.55);
    transition: transform 0.25s ease;
    filter: drop-shadow(0 6px 14px rgba(0, 0, 0, 0.25));
  }
  .gcard:hover .art :global(svg) {
    transform: scale(1.7);
  }
  .gcard .art .pin {
    position: absolute;
    top: 12px;
    left: 12px;
    font-family: var(--font-mono);
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: rgba(11, 15, 23, 0.9);
    background: rgba(255, 255, 255, 0.92);
    padding: 4px 8px;
    border-radius: var(--radius-sm);
  }
  .gcard .body {
    padding: 18px 20px 20px;
    display: flex;
    flex-direction: column;
    gap: 6px;
    flex: 1;
  }
  .gcard .body h3 {
    font-size: 18px;
    font-weight: 700;
    letter-spacing: -0.015em;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }
  .gcard .body h3 .badge {
    font-family: var(--font-sans);
    font-size: 9.5px;
    font-weight: 700;
    background: var(--paper-2);
    color: var(--ink-soft);
    padding: 4px 8px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--line-1);
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  .gcard .meta {
    font-family: var(--font-mono);
    color: var(--ink-faint);
    font-size: 11px;
    letter-spacing: 0.04em;
    margin-bottom: 4px;
  }
  .gcard .desc {
    color: var(--ink-soft);
    font-size: 13.5px;
    line-height: 1.55;
    flex: 1;
  }
  .gcard .go {
    margin-top: 12px;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-family: var(--font-sans);
    color: var(--tk-blue);
    font-weight: 700;
    font-size: 12px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
  }
  .gcard:hover .go {
    color: var(--tk-blue-deep);
  }
  .gcard .go::after {
    content: '→';
    transition: transform 0.18s ease;
  }
  .gcard:hover .go::after {
    transform: translateX(4px);
  }

  .gcard.soon {
    cursor: default;
  }
  .gcard.soon:hover {
    transform: none;
  }
  .gcard.soon .art {
    background:
      repeating-linear-gradient(
        135deg,
        rgba(255, 255, 255, 0.04) 0 12px,
        transparent 12px 24px
      ),
      var(--accent);
  }
  .gcard.soon .art .pin {
    background: rgba(11, 15, 23, 0.65);
    color: rgba(255, 255, 255, 0.85);
    border: 1px solid rgba(255, 255, 255, 0.15);
  }
  .gcard.soon .go {
    color: var(--ink-faint);
  }
  .gcard.soon .go::after {
    content: '';
  }

  .gcard.janken {
    --accent: var(--tk-blue);
  }
  .gcard.mint-soon {
    --accent: var(--mint);
  }
  .gcard.sky-soon {
    --accent: var(--sky);
  }
  .gcard.coral-soon {
    --accent: var(--coral);
  }
  .gcard.lavender-soon {
    --accent: var(--lavender);
  }

  .site-footer {
    max-width: 1280px;
    margin: 32px auto 24px;
    padding: 32px 0 16px;
    border-top: 1px solid var(--line-1);
    text-align: center;
    color: var(--ink-faint);
    font-family: var(--font-mono);
    font-size: 11px;
    letter-spacing: 0.06em;
  }

  @media (max-width: 820px) {
    main {
      padding: 0 16px;
    }
    :global(body > #topbar) {
      padding: 0 16px;
    }
    .games-header {
      margin: 16px auto 24px;
    }
  }
</style>
