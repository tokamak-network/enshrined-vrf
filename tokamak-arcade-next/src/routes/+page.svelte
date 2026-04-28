<script lang="ts">
  import { i18n } from '$lib/i18n.svelte';
  import Topbar from '$lib/components/Topbar.svelte';
  import { jankenMascot } from '$lib/mascots';
  import { TOKAMAK_SYMBOL_DATA_URI } from '$lib/brand';

  // ─── Feature card icons (How it works) ────────────────────────────
  // Stroke = currentColor so they pick up the tk-blue from `.feature .icon`.
  const chipIcon = `
<svg viewBox="0 0 32 32" width="36" height="36" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <rect x="8" y="8" width="16" height="16" rx="2"/>
  <path d="M3 12h5M3 20h5M24 12h5M24 20h5M12 3v5M20 3v5M12 24v5M20 24v5"/>
  <circle cx="16" cy="16" r="2.5" fill="currentColor"/>
</svg>`;
  const boltIcon = `
<svg viewBox="0 0 32 32" width="36" height="36" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M18 3 L7 18 h7 l-2 11 L25 14 h-7 z" fill="currentColor"/>
</svg>`;
  const shieldCheckIcon = `
<svg viewBox="0 0 32 32" width="36" height="36" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M16 3 L27 7 v9 c0 6 -4 11 -11 13 C9 27 5 22 5 16 V7 z"/>
  <path d="M11 16 l4 4 l7 -7"/>
</svg>`;

  // ─── Soon-tile glyphs (Upcoming Games) ────────────────────────────
  // Dark stroke at low opacity so the glyph reads against the pastel art.
  const bracketIcon = `
<svg viewBox="0 0 64 64" width="84" height="84" fill="none" stroke="rgba(11,15,23,0.6)" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
  <rect x="6" y="14" width="16" height="6" rx="1"/>
  <rect x="6" y="26" width="16" height="6" rx="1"/>
  <rect x="6" y="38" width="16" height="6" rx="1"/>
  <rect x="6" y="50" width="16" height="6" rx="1"/>
  <rect x="42" y="20" width="16" height="6" rx="1"/>
  <rect x="42" y="44" width="16" height="6" rx="1"/>
  <path d="M22 17 h6 v9 h-6 M22 29 h6 v-9 M28 23 h8 v17 h-8 v-9 M22 41 h6 v9 h-6 M22 53 h6 v-9 M28 47 h14"/>
</svg>`;
  const kartIcon = `
<svg viewBox="0 0 64 64" width="84" height="84" fill="none" stroke="rgba(11,15,23,0.6)" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
  <path d="M8 38 L14 24 h26 l8 14 z"/>
  <path d="M24 24 v-6 h10 v6"/>
  <circle cx="18" cy="44" r="6"/>
  <circle cx="46" cy="44" r="6"/>
  <path d="M48 26 l6 -2 M14 28 l-6 -2"/>
</svg>`;
  const giftIcon = `
<svg viewBox="0 0 64 64" width="84" height="84" fill="none" stroke="rgba(11,15,23,0.6)" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
  <rect x="10" y="22" width="44" height="32" rx="2"/>
  <rect x="6" y="18" width="52" height="8" rx="1"/>
  <path d="M32 18 v36"/>
  <path d="M32 18 c-4 -8 -14 -6 -12 0 c2 4 8 4 12 0 z"/>
  <path d="M32 18 c4 -8 14 -6 12 0 c-2 4 -8 4 -12 0 z"/>
</svg>`;
  const wordIcon = `
<svg viewBox="0 0 64 64" width="84" height="84" fill="none" stroke="rgba(11,15,23,0.6)" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
  <rect x="6" y="22" width="16" height="20" rx="2"/>
  <rect x="24" y="22" width="16" height="20" rx="2"/>
  <rect x="42" y="22" width="16" height="20" rx="2"/>
  <path d="M11 30 l3 5 l3 -5"/>
  <path d="M28 28 l4 8 l4 -8 M30 33 h4"/>
  <path d="M48 28 v8 M48 28 l4 4 l-4 4"/>
</svg>`;

  type SoonGame = {
    cls: string;
    name: string;
    badge: string;
    meta: string;
    accent: string;
    desc: string;
    icon: string;
  };

  const SOON: SoonGame[] = [
    {
      cls: 'mint',
      name: 'Bracket Brawl',
      badge: 'Soon',
      meta: 'tournament',
      accent: 'var(--mint)',
      desc: 'One VRF call seats a 64-player tournament bracket — provably fair pairings, end to end.',
      icon: bracketIcon
    },
    {
      cls: 'sky',
      name: 'L2 Karts',
      badge: 'Soon',
      meta: 'race · vrf',
      accent: 'var(--sky)',
      desc: 'Random track layout, random boosts. One round, one result — settled inside the play tx.',
      icon: kartIcon
    },
    {
      cls: 'coral',
      name: 'Mystery Box',
      badge: 'Soon',
      meta: 'loot pull',
      accent: 'var(--coral)',
      desc: 'A gacha with provably uniform odds. Loot tables and pull logic stay 100% on-chain.',
      icon: giftIcon
    },
    {
      cls: 'lavender',
      name: 'Word Wager',
      badge: 'Soon',
      meta: 'word puzzle',
      accent: 'var(--lavender)',
      desc: 'A daily match seed from VRF. Same seed → same board for everyone, no server in the loop.',
      icon: wordIcon
    }
  ];
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
        <a class="btn-primary" href="/jankenman/">
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

  <section class="section" id="how">
    <div class="section-head">
      <h2>{i18n.t('landing.featuresKicker')}</h2>
    </div>
    <div class="feature-strip-grid">
      <div class="feature">
        <div class="head">
          <div class="icon">{@html chipIcon}</div>
          <h3>{i18n.t('landing.f1.t')}</h3>
        </div>
        <p>{@html i18n.t('landing.f1.b')}</p>
      </div>
      <div class="feature">
        <div class="head">
          <div class="icon">{@html boltIcon}</div>
          <h3>{i18n.t('landing.f2.t')}</h3>
        </div>
        <p>{@html i18n.t('landing.f2.b')}</p>
      </div>
      <div class="feature">
        <div class="head">
          <div class="icon">{@html shieldCheckIcon}</div>
          <h3>{i18n.t('landing.f3.t')}</h3>
        </div>
        <p>{@html i18n.t('landing.f3.b')}</p>
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
            <div class="glyph">{@html s.icon}</div>
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
    </div>
  </footer>
</main>

<style>
  :global(body) {
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
    margin: 16px auto 80px;
    border-radius: var(--radius-xl);
    background:
      radial-gradient(700px 420px at 90% 20%, rgba(42, 114, 229, 0.18), transparent 65%),
      radial-gradient(560px 360px at 0% 100%, rgba(111, 168, 255, 0.16), transparent 70%),
      linear-gradient(160deg, #0f1623 0%, #0b0f17 100%);
    border: 1px solid var(--line-1);
    padding: 56px 56px 56px;
    position: relative;
    overflow: hidden;
    display: grid;
    grid-template-columns: minmax(0, 1.3fr) minmax(0, 1fr);
    align-items: start;
    gap: 48px;
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
      padding: 40px 24px 48px;
      gap: 32px;
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
  .tile.soon .art .glyph {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    z-index: 1;
    pointer-events: none;
  }
  .tile.soon .art .glyph :global(svg) {
    filter: drop-shadow(0 2px 6px rgba(0, 0, 0, 0.18));
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
  .feature .head {
    display: flex;
    align-items: center;
    gap: 14px;
  }
  .feature .icon {
    color: var(--tk-blue);
    width: 36px;
    height: 36px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
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
      padding: 32px 20px 40px;
      margin: 12px auto 56px;
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
