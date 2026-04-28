<script lang="ts">
  import { i18n } from '$lib/i18n.svelte';
  import Topbar from '$lib/components/Topbar.svelte';
  import { jankenMascot } from '$lib/mascots';
  import { TOKAMAK_SYMBOL_DATA_URI } from '$lib/brand';

  type Game = {
    cls: string;
    name: string;
    badge: string;
    meta: string;
    href: string;
    desc: string;
    mascot: typeof jankenMascot;
  };
  type SoonGame = {
    cls: string;
    name: string;
    badge: string;
    meta: string;
    accent: string;
    desc: string;
  };

  const GAMES: Game[] = [
    {
      cls: 'janken',
      name: 'Jankenman',
      badge: 'DeFi',
      meta: 'RPS + LP pool',
      mascot: jankenMascot,
      href: '/jankenman/',
      desc: '가위바위보 + 룰렛. 단일 VRF 호출 + 세션키로 서명 없는 플레이.'
    }
  ];

  const SOON: SoonGame[] = [
    {
      cls: 'mint',
      name: 'Bracket Brawl',
      badge: 'Soon',
      meta: 'tournament',
      accent: 'var(--mint)',
      desc: '단일 VRF 호출로 64인 토너먼트 대진을 결정.'
    },
    {
      cls: 'sky',
      name: 'L2 Karts',
      badge: 'Soon',
      meta: 'race · vrf',
      accent: 'var(--sky)',
      desc: '랜덤 트랙 + 랜덤 부스트 — 한 라운드, 한 결과.'
    },
    {
      cls: 'coral',
      name: 'Mystery Box',
      badge: 'Soon',
      meta: 'loot pull',
      accent: 'var(--coral)',
      desc: '균등 분포 검증 가능한 가챠. 풀이 100% 온체인.'
    },
    {
      cls: 'lavender',
      name: 'Word Wager',
      badge: 'Soon',
      meta: 'word puzzle',
      accent: 'var(--lavender)',
      desc: 'VRF로 매일 매치 시드. 같은 시드 → 같은 게임판.'
    }
  ];

  const FEATURED = GAMES.filter((g) => g.cls === 'janken');
</script>

<svelte:head>
  <title>{i18n.t('landing.title')}</title>
</svelte:head>

<div id="topbar">
  <Topbar hubHref="/" />
</div>

<main>
  <section class="hero">
    <div>
      <span class="eyebrow">
        <span class="live-dot"></span>
        <span>{i18n.t('landing.eyebrow')}</span>
      </span>
      <h1>{@html i18n.t('landing.h1')}</h1>
      <p class="lede">{@html i18n.t('landing.lede')}</p>
      <div class="cta-row">
        <a class="btn-primary" href="/games/">
          <span>{i18n.t('landing.cta.enter')}</span>
          <span aria-hidden="true">→</span>
        </a>
        <a
          class="btn-ghost"
          href="https://enshrined-vrf-docs.vercel.app/"
          target="_blank"
          rel="noopener"
        >
          {i18n.t('landing.cta.how')}
        </a>
      </div>
    </div>
    <a class="hero-feature" href="/jankenman/" aria-label="Jankenman — featured game">
      <span class="badge">Featured</span>
      <div class="mascot">{@html jankenMascot({ size: 200 })}</div>
      <div class="meta">
        <h3>Jankenman</h3>
        <p>RPS + roulette · LP pool · session keys</p>
      </div>
    </a>
  </section>

  <section class="section" id="featured">
    <div class="section-head">
      <h2>{i18n.t('landing.featured.t')}</h2>
      <a class="head-link" href="/games/">{i18n.t('landing.seeAll')}</a>
    </div>
    <div class="scroll-row row-featured">
      {#each FEATURED as g (g.cls)}
        <a class="tile {g.cls}" href={g.href} aria-label={g.name}>
          <div class="art">
            <span class="pin">{g.badge}</span>
            {@html g.mascot({ size: 110 })}
          </div>
          <div class="body">
            <h4>{g.name}</h4>
            <div class="meta">{g.meta}</div>
            <div class="desc">{g.desc}</div>
          </div>
        </a>
      {/each}
    </div>
  </section>

  <section class="section" id="all-games">
    <div class="section-head">
      <h2>{i18n.t('landing.preview.t')}</h2>
      <a class="head-link" href="/games/">{i18n.t('landing.seeAll')}</a>
    </div>
    <div class="scroll-row">
      {#each GAMES as g (g.cls)}
        <a class="tile {g.cls}" href={g.href} aria-label={g.name}>
          <div class="art">
            <span class="pin">{g.badge}</span>
            {@html g.mascot({ size: 110 })}
          </div>
          <div class="body">
            <h4>{g.name}</h4>
            <div class="meta">{g.meta}</div>
            <div class="desc">{g.desc}</div>
          </div>
        </a>
      {/each}
    </div>
  </section>

  <section class="section" id="how">
    <div class="section-head">
      <h2>{i18n.t('landing.featuresKicker')}</h2>
    </div>
    <div class="feature-strip-grid">
      <div class="feature">
        <div class="num">01</div>
        <h3>{i18n.t('landing.f1.t')}</h3>
        <p>{i18n.t('landing.f1.b')}</p>
      </div>
      <div class="feature">
        <div class="num">02</div>
        <h3>{i18n.t('landing.f2.t')}</h3>
        <p>{i18n.t('landing.f2.b')}</p>
      </div>
      <div class="feature">
        <div class="num">03</div>
        <h3>{i18n.t('landing.f3.t')}</h3>
        <p>{i18n.t('landing.f3.b')}</p>
      </div>
    </div>
  </section>

  <section class="section" id="upcoming">
    <div class="section-head">
      <h2>{i18n.t('landing.upcoming')}</h2>
      <a
        class="head-link"
        href="https://enshrined-vrf-docs.vercel.app/"
        target="_blank"
        rel="noopener">Roadmap</a
      >
    </div>
    <div class="scroll-row">
      {#each SOON as s (s.cls)}
        <div class="tile soon" style="--accent:{s.accent}">
          <div class="art">
            <span class="pin soon-badge">{s.badge}</span>
          </div>
          <div class="body">
            <h4>{s.name} <span class="badge">soon</span></h4>
            <div class="meta">{s.meta}</div>
            <div class="desc">{s.desc}</div>
          </div>
        </div>
      {/each}
    </div>
  </section>

  <section class="final-cta">
    <div>
      <div class="kicker">{i18n.t('landing.finalKicker')}</div>
      <h2>{i18n.t('landing.final.t')}</h2>
      <p>{@html i18n.t('landing.final.b')}</p>
    </div>
    <div class="cta-side">
      <a class="btn-primary" href="/games/">
        <span>{i18n.t('landing.cta.enter')}</span>
        <span aria-hidden="true">→</span>
      </a>
      <span class="stat">1 game live · 4 in development</span>
    </div>
  </section>

  <footer class="site-footer">
    <div class="footer-main">
      <div class="footer-col footer-col-brand">
        <div class="footer-brand">
          <span class="logo-chip">
            <img src={TOKAMAK_SYMBOL_DATA_URI} alt="Tokamak Network" />
          </span>
          <span>Tokamak <b>Arcade</b></span>
        </div>
        <p class="footer-sub">
          Backed by Tokamak Network — L2 infrastructure &amp; developer tooling for the next
          generation of onchain apps.
        </p>
      </div>
      <nav class="footer-col" aria-label="Resources">
        <h4>Resources</h4>
        <a href="https://enshrined-vrf-docs.vercel.app/" target="_blank" rel="noopener">Docs</a>
        <a href="https://medium.com/tokamak-network" target="_blank" rel="noopener">Medium</a>
      </nav>
      <nav class="footer-col" aria-label="Community">
        <h4>Community</h4>
        <a href="https://twitter.com/tokamak_network" target="_blank" rel="noopener">X (Twitter)</a>
        <a href="https://discord.com/invite/J4chV2zuAK" target="_blank" rel="noopener">Discord</a>
        <a href="https://t.me/tokamak_network" target="_blank" rel="noopener">Telegram</a>
      </nav>
      <nav class="footer-col" aria-label="Code">
        <h4>Code</h4>
        <a href="https://github.com/tokamak-network" target="_blank" rel="noopener">GitHub</a>
        <a href="https://www.linkedin.com/company/tokamaknetwork/" target="_blank" rel="noopener">
          LinkedIn
        </a>
      </nav>
    </div>
    <div class="footer-bottom">
      <span>© Tokamak Network</span>
      <span>
        Tokamak Arcade — an
        <a href="https://enshrined-vrf-docs.vercel.app/" target="_blank" rel="noopener">
          Enshrined VRF
        </a>
        demo
      </span>
    </div>
  </footer>
</main>

<style>
  body {
    padding: 16px 0 0;
    background:
      radial-gradient(1100px 600px at 85% -10%, rgba(42, 114, 229, 0.08), transparent 70%),
      radial-gradient(900px 500px at -10% 30%, rgba(111, 168, 255, 0.06), transparent 70%),
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

  .hero {
    max-width: 1280px;
    margin: 24px auto 96px;
    border-radius: var(--radius-xl);
    background:
      radial-gradient(700px 420px at 90% 20%, rgba(42, 114, 229, 0.18), transparent 65%),
      radial-gradient(560px 360px at 0% 100%, rgba(111, 168, 255, 0.16), transparent 70%),
      linear-gradient(160deg, #0f1623 0%, #0b0f17 100%);
    border: 1px solid var(--line-1);
    padding: 80px 56px 72px;
    position: relative;
    overflow: hidden;
    min-height: 520px;
    display: grid;
    grid-template-columns: minmax(0, 1.3fr) minmax(0, 1fr);
    align-items: center;
    gap: 56px;
  }
  .hero::after {
    content: '';
    position: absolute;
    inset: 0;
    background-image:
      linear-gradient(var(--line-1) 1px, transparent 1px),
      linear-gradient(90deg, var(--line-1) 1px, transparent 1px);
    background-size: 56px 56px;
    mask-image: radial-gradient(ellipse at 50% 50%, #000 30%, transparent 75%);
    pointer-events: none;
    opacity: 0.4;
  }
  .hero > * {
    position: relative;
    z-index: 1;
  }

  .hero .eyebrow {
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
    margin-bottom: 28px;
  }
  .hero .eyebrow .live-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--tk-blue);
    box-shadow: 0 0 0 4px var(--glow);
    animation: tokamak-pulse 2.4s ease-in-out infinite;
  }

  .hero h1 {
    font-size: clamp(44px, 6.5vw, 88px);
    line-height: 1;
    font-weight: 700;
    letter-spacing: -0.03em;
    color: var(--ink);
    max-width: 14ch;
  }
  .hero :global(h1 .kw) {
    color: var(--tk-blue);
  }

  .hero .lede {
    margin-top: 22px;
    color: var(--ink-soft);
    font-size: 17px;
    font-weight: 400;
    line-height: 1.6;
    max-width: 48ch;
  }
  .hero .lede :global(code) {
    font-size: 0.92em;
    background: rgba(255, 255, 255, 0.06);
    border: 1px solid var(--line-1);
  }

  .hero .cta-row {
    display: inline-flex;
    gap: 10px;
    margin-top: 32px;
    flex-wrap: wrap;
  }
  .btn-primary,
  .btn-ghost {
    appearance: none;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 10px;
    padding: 14px 26px;
    border-radius: var(--radius-md);
    font-family: var(--font-sans);
    font-weight: 700;
    font-size: 14.5px;
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
    box-shadow: 0 0 0 6px var(--glow-soft);
  }
  .btn-primary:active {
    transform: translateY(1px);
  }
  .btn-ghost {
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid var(--line-2);
    color: var(--ink);
  }
  .btn-ghost:hover {
    border-color: var(--line-3);
    background: rgba(255, 255, 255, 0.08);
    color: var(--ink);
    text-decoration: none;
  }

  .hero-feature {
    position: relative;
    aspect-ratio: 4 / 5;
    border-radius: var(--radius-xl);
    overflow: hidden;
    border: 1px solid var(--line-2);
    background:
      radial-gradient(circle at 30% 25%, rgba(255, 255, 255, 0.18), transparent 55%),
      linear-gradient(180deg, var(--tk-blue) 0%, var(--tk-blue-deep) 100%);
    display: grid;
    place-items: center;
    box-shadow:
      0 30px 80px rgba(0, 0, 0, 0.55),
      0 0 0 1px rgba(42, 114, 229, 0.2),
      0 0 60px rgba(42, 114, 229, 0.18);
    transform: rotate(-2deg);
  }
  .hero-feature .badge {
    position: absolute;
    top: 16px;
    left: 16px;
    font-family: var(--font-mono);
    font-size: 10.5px;
    font-weight: 600;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: rgba(11, 15, 23, 0.85);
    background: rgba(255, 255, 255, 0.85);
    padding: 5px 10px;
    border-radius: var(--radius-sm);
  }
  .hero-feature .meta {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    padding: 18px 20px;
    background: linear-gradient(0deg, rgba(0, 0, 0, 0.55), transparent);
    color: #fff;
  }
  .hero-feature .meta h3 {
    color: #fff;
    font-size: 22px;
    font-weight: 700;
    letter-spacing: -0.015em;
    margin-bottom: 4px;
  }
  .hero-feature .meta p {
    color: rgba(255, 255, 255, 0.85);
    font-size: 12.5px;
    font-weight: 500;
  }
  .hero-feature .mascot {
    transform: scale(2.1);
    filter: drop-shadow(0 12px 24px rgba(0, 0, 0, 0.45));
  }

  @media (max-width: 960px) {
    .hero {
      grid-template-columns: 1fr;
      padding: 56px 28px;
      gap: 40px;
    }
    .hero-feature {
      max-width: 360px;
      justify-self: start;
      aspect-ratio: 4 / 4.5;
    }
  }

  .section {
    max-width: 1280px;
    margin: 0 auto 96px;
  }
  .section-head {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    margin-bottom: 24px;
    gap: 12px;
    flex-wrap: wrap;
  }
  .section-head h2 {
    font-family: var(--font-sans);
    font-weight: 700;
    font-size: clamp(22px, 2.6vw, 30px);
    letter-spacing: -0.02em;
    color: var(--ink);
  }
  .section-head .head-link {
    font-family: var(--font-sans);
    font-size: 12px;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--ink-soft);
    text-decoration: none;
    transition:
      color 0.15s ease,
      transform 0.15s ease;
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }
  .section-head .head-link:hover {
    color: var(--tk-blue);
    text-decoration: none;
  }
  .section-head .head-link::after {
    content: '→';
    transition: transform 0.15s ease;
  }
  .section-head .head-link:hover::after {
    transform: translateX(4px);
  }

  .scroll-row.row-featured > .tile {
    width: 360px;
    min-height: 340px;
  }

  .tile {
    width: 240px;
    background: var(--paper);
    border: 1px solid var(--line-1);
    border-radius: var(--radius-lg);
    overflow: hidden;
    text-decoration: none;
    color: var(--ink);
    display: flex;
    flex-direction: column;
    transition:
      background 0.18s ease,
      border-color 0.18s ease,
      transform 0.18s ease;
  }
  .tile:hover {
    background: var(--paper-2);
    border-color: var(--line-2);
    transform: translateY(-3px);
    color: var(--ink);
    text-decoration: none;
  }
  .tile .art {
    aspect-ratio: 1 / 1;
    display: grid;
    place-items: center;
    background:
      linear-gradient(180deg, rgba(0, 0, 0, 0) 50%, rgba(0, 0, 0, 0.3) 100%),
      var(--accent);
    position: relative;
    overflow: hidden;
  }
  .tile .art::after {
    content: '';
    position: absolute;
    inset: 0;
    background: radial-gradient(circle at 75% 25%, rgba(255, 255, 255, 0.2), transparent 60%);
    pointer-events: none;
  }
  .tile .art :global(svg) {
    position: relative;
    z-index: 1;
    transform: scale(1.4);
    transition: transform 0.25s ease;
  }
  .tile:hover .art :global(svg) {
    transform: scale(1.55);
  }
  .tile .art .pin {
    position: absolute;
    top: 10px;
    left: 10px;
    z-index: 2;
    font-family: var(--font-mono);
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: rgba(11, 15, 23, 0.9);
    background: rgba(255, 255, 255, 0.92);
    padding: 4px 8px;
    border-radius: var(--radius-sm);
  }
  .tile .body {
    padding: 14px 16px 16px;
    display: flex;
    flex-direction: column;
    gap: 4px;
    flex: 1;
  }
  .tile .body h4 {
    font-family: var(--font-sans);
    font-size: 15px;
    font-weight: 700;
    letter-spacing: -0.01em;
    color: var(--ink);
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 8px;
  }
  .tile .body h4 .badge {
    font-family: var(--font-sans);
    font-size: 9.5px;
    font-weight: 700;
    background: var(--paper-2);
    color: var(--ink-soft);
    padding: 3px 7px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--line-1);
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  .tile .body .meta {
    font-family: var(--font-mono);
    font-size: 11px;
    color: var(--ink-faint);
    font-weight: 400;
  }
  .tile .body .desc {
    font-size: 12.5px;
    color: var(--ink-soft);
    line-height: 1.45;
    margin-top: 4px;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .row-featured .tile .art {
    aspect-ratio: 16 / 9;
  }
  .row-featured .tile .art :global(svg) {
    transform: scale(1.7);
  }
  .row-featured .tile:hover .art :global(svg) {
    transform: scale(1.85);
  }

  .tile.janken {
    --accent: var(--tk-blue);
  }

  .tile.soon {
    opacity: 0.85;
  }
  .tile.soon .art {
    background:
      repeating-linear-gradient(
        135deg,
        rgba(255, 255, 255, 0.04) 0 12px,
        transparent 12px 24px
      ),
      var(--accent);
  }
  .tile.soon .badge.soon-badge {
    background: rgba(11, 15, 23, 0.65);
    color: rgba(255, 255, 255, 0.85);
    border-color: rgba(255, 255, 255, 0.15);
  }

  .feature-strip-grid {
    display: grid;
    gap: 16px;
    grid-template-columns: repeat(3, 1fr);
  }
  @media (max-width: 820px) {
    .feature-strip-grid {
      grid-template-columns: 1fr;
    }
  }
  .feature {
    padding: 32px 28px 36px;
    background: var(--paper);
    border: 1px solid var(--line-1);
    border-radius: var(--radius-lg);
    display: flex;
    flex-direction: column;
    gap: 14px;
    transition:
      background 0.18s ease,
      border-color 0.18s ease;
    position: relative;
    overflow: hidden;
  }
  .feature:hover {
    background: var(--paper-2);
    border-color: var(--line-2);
  }
  .feature::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 1px;
    background: linear-gradient(90deg, transparent, var(--tk-blue), transparent);
    opacity: 0;
    transition: opacity 0.2s ease;
  }
  .feature:hover::before {
    opacity: 0.6;
  }
  .feature .num {
    font-family: var(--font-mono);
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--tk-blue);
  }
  .feature h3 {
    font-family: var(--font-sans);
    font-weight: 700;
    font-size: 22px;
    letter-spacing: -0.02em;
    line-height: 1.2;
    color: var(--ink);
  }
  .feature p {
    font-family: var(--font-sans);
    color: var(--ink-soft);
    font-weight: 400;
    font-size: 14.5px;
    line-height: 1.6;
  }

  .final-cta {
    max-width: 1280px;
    margin: 0 auto 64px;
    padding: 64px 56px;
    background:
      radial-gradient(700px 360px at 100% 0%, rgba(42, 114, 229, 0.18), transparent 65%),
      linear-gradient(160deg, #131927 0%, #0b0f17 100%);
    border: 1px solid var(--line-1);
    border-radius: var(--radius-xl);
    position: relative;
    overflow: hidden;
    display: grid;
    grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr);
    gap: 48px;
    align-items: center;
  }
  @media (max-width: 820px) {
    .final-cta {
      grid-template-columns: 1fr;
      padding: 40px 28px;
      gap: 28px;
    }
  }

  .final-cta .kicker {
    font-family: var(--font-mono);
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--tk-blue);
    margin-bottom: 14px;
    display: inline-flex;
    align-items: center;
    gap: 10px;
  }
  .final-cta .kicker::before {
    content: '';
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--tk-blue);
    box-shadow: 0 0 0 4px var(--glow);
  }
  .final-cta h2 {
    font-family: var(--font-sans);
    font-weight: 700;
    font-size: clamp(28px, 4vw, 48px);
    line-height: 1.05;
    letter-spacing: -0.02em;
    color: var(--ink);
  }
  .final-cta p {
    color: var(--ink-soft);
    font-size: 15.5px;
    font-weight: 400;
    line-height: 1.6;
    margin-top: 14px;
    max-width: 60ch;
  }
  .final-cta p :global(code) {
    background: rgba(255, 255, 255, 0.08);
    color: #fff;
    font-size: 0.9em;
  }
  .final-cta .cta-side {
    display: flex;
    flex-direction: column;
    gap: 12px;
    align-items: flex-start;
  }
  .final-cta .stat {
    font-family: var(--font-mono);
    font-size: 11px;
    color: var(--ink-faint);
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .site-footer {
    max-width: 1280px;
    margin: 32px auto 24px;
    padding: 48px 0 24px;
    border-top: 1px solid var(--line-1);
    font-family: var(--font-sans);
    color: var(--ink-soft);
  }
  .footer-main {
    display: grid;
    grid-template-columns: 1.6fr 1fr 1fr 1fr;
    gap: 56px;
    padding-bottom: 32px;
  }
  .footer-col-brand {
    padding-right: 16px;
  }
  .footer-brand {
    display: flex;
    align-items: center;
    gap: 10px;
    font-family: var(--font-sans);
    font-size: 15px;
    font-weight: 700;
    color: var(--ink);
    margin-bottom: 14px;
    letter-spacing: -0.005em;
  }
  .footer-brand .logo-chip {
    width: 24px;
    height: 24px;
    display: grid;
    place-items: center;
  }
  .footer-brand .logo-chip img {
    width: 100%;
    height: 100%;
    object-fit: contain;
    filter: brightness(0) invert(1);
  }
  .footer-sub {
    color: var(--ink-soft);
    font-size: 13.5px;
    line-height: 1.6;
    font-weight: 400;
    max-width: 360px;
  }
  .footer-col h4 {
    font-family: var(--font-sans);
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--ink);
    margin-bottom: 14px;
  }
  .footer-col a {
    display: block;
    color: var(--ink-soft);
    text-decoration: none;
    padding: 5px 0;
    font-size: 13.5px;
    font-weight: 500;
    transition: color 0.15s ease;
  }
  .footer-col a:hover {
    color: var(--tk-blue);
    text-decoration: none;
  }
  .footer-bottom {
    display: flex;
    justify-content: space-between;
    align-items: center;
    flex-wrap: wrap;
    gap: 10px;
    padding-top: 18px;
    border-top: 1px solid var(--line-1);
    color: var(--ink-faint);
    font-family: var(--font-mono);
    font-size: 11px;
    letter-spacing: 0.04em;
  }
  .footer-bottom a {
    color: var(--ink-soft);
    text-decoration: none;
  }
  .footer-bottom a:hover {
    color: var(--tk-blue);
  }

  @media (max-width: 820px) {
    main {
      padding: 0 16px;
    }
    :global(body > #topbar) {
      padding: 0 16px;
    }
    .hero {
      padding: 44px 24px 56px;
      margin: 16px auto 64px;
    }
    .section {
      margin-bottom: 64px;
    }
    .footer-main {
      grid-template-columns: 1fr 1fr;
      gap: 32px;
    }
    .footer-col-brand {
      grid-column: 1 / -1;
      padding-right: 0;
    }
  }

  section {
    scroll-margin-top: 80px;
  }
</style>
