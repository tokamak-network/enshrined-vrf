# Tokamak Arcade — Design System

A dark, immersive game-platform design language inspired by GAMES.GG. High-
contrast, content-heavy, modular — built around the **Tokamak Network brand
blue** as the single primary accent on a deep navy canvas, with edge-to-edge
game artwork as the primary visual unit.

This document is the source of truth for the look-and-feel of every page in
`tokamak-arcade/`. Per-game pages inherit the system through
`shared/tokamak.css`; landing and hub pages compose its tokens directly.

---

## Brand stance

- **Voice:** "play fair, play cute" — confident, gaming-native, but never
  shouty. We are an *arcade*, not a casino. Copy stays neutral: "play",
  "round", "match" instead of "bet", "wager", "casino".
- **Visual stance:** dark theatre + brand spotlight. The canvas recedes; game
  artwork and the primary action take all the attention.
- **Identity anchor:** Tokamak Network. The brand blue (`#2A72E5`, taken
  directly from the official Tokamak symbol) is the one primary color across
  every CTA, focus ring, and live-state indicator. Semantic green is
  preserved — but only for win/success cues, never as the brand mark.

---

## Color tokens

```
PRIMARY   #2A72E5   tokamak blue   CTA, active states, focus rings, links
PRIMARY-D #1A56B8   blue deep      hover/active for primary
PRIMARY-I #FFFFFF   on-blue ink    text on tokamak-blue surfaces

CANVAS    #0B0F17   deep navy      page background
PAPER     #131927   surface 1      cards, panels
PAPER-2   #1B2336   surface 2      hover, elevated, code blocks

INK       #FFFFFF   primary text   headings, body
INK-SOFT  #A8B0C0   secondary      ledes, descriptions, meta
INK-FAINT #6B7280   tertiary       footer, timestamps, low-priority

ERROR     #FF4D5E
SUCCESS   #00CC66   semantic green — wins, "live" pills, OK status only
SUCCESS-D #00A653   deep green     win-text color, success borders
WARN      #FFC857
```

The CSS exposes these as `--tk-blue`, `--tk-blue-deep`, `--tk-blue-ink`,
`--success`, `--success-deep`, `--glow` (blue, used for primary focus rings),
and `--success-glow` (green, used for win states). The `--tk-blue` variable
name is preserved across pages so per-game stylesheets keep working.

### Per-game accent tints

Each game owns one solid, vibrant color used as the **mascot tile** background
and as a thin 1px accent strip on cards. Tints are deliberately saturated so
they punch out of the dark canvas like neon panels.

```
flip      butter   #FFD466
dice      pink     #FF6B9F
plinko    sky      #6FA8FF
lottery   lavender #B69BFF
janken    blue     #2A72E5    (the primary — Jankenman is the marquee game)
pongy     coral    #FF8866
```

### Usage rules

- Pages use **PRIMARY** sparingly — typically one CTA and one focus ring per
  viewport. Never paint large areas with brand blue; it is a spotlight, not
  a wall.
- Cards default to **PAPER**; on hover lift to **PAPER-2**.
- Borders are `rgba(255, 255, 255, 0.06)` (resting) and
  `rgba(255, 255, 255, 0.12)` (hover/focus). Never use solid grays.
- Primary glow (focus rings, hero spotlights) uses
  `rgba(42, 114, 229, 0.30)` at 4px. Win-state glow uses
  `rgba(0, 204, 102, 0.30)` at the same size.

---

## Typography

System sans across the board, JetBrains Mono only for code/hashes.

```
font-sans:  -apple-system, "system-ui", "Pretendard", "Noto Sans KR",
            "Helvetica Neue", Arial, sans-serif
font-mono:  "JetBrains Mono", "SF Mono", Menlo, Consolas, monospace
```

### Scale

```
display    clamp(48px, 7vw, 96px)   wt 600   tracking -0.025em   line 1.0
h1         clamp(34px, 5vw, 56px)   wt 600   tracking -0.025em   line 1.05
h2         clamp(24px, 3vw, 36px)   wt 600   tracking -0.02em    line 1.15
h3         20px                     wt 600   tracking -0.015em   line 1.25
body-lg    17px                     wt 400                       line 1.55
body       15px                     wt 400                       line 1.5
meta       12px                     wt 600   tracking 0.05em     UPPERCASE
mono       11.5–13px                wt 400
```

### Headlines

- Headlines stay in **INK** (white). Never tint a full headline neon — use
  `<span class="kw">` to highlight at most one or two keywords per heading.
- Display text on the hero may sit on a darker gradient; ensure at minimum
  4.5:1 contrast over the busiest pixel of any background image.

---

## Layout

### Container

```
max-width: 1280px
gutter:    32px (desktop) / 20px (≤640px)
section gap: 96px (desktop) / 56px (mobile) between major bands
```

### Grid

- Card grid: `repeat(auto-fill, minmax(280px, 1fr))` with 16px gap.
- Carousel rows: horizontal flex, `scroll-snap-type: x mandatory`, snap
  alignment `start`, 16px gap, masked fade on right edge.

### Spacing rhythm

```
sm  8px       inside small chips, icon gaps
md  16px      card padding (compact), grid gap
lg  24px      card padding (default)
xl  32px      panel padding
2xl 56px      between sections inside a band
3xl 96px      between major bands
```

### Radii

```
sm  4px       chips, badges, code
md  8px       buttons, inputs
lg  16px      cards, panels
xl  24px      hero panels, featured banners
```

Sharp 4–8px on UI; generous 16–24px on the big visual blocks. Never mix.

---

## Components

### Top bar

Sticky, dark solid `#0B0F17` with a 1px bottom border at
`rgba(255, 255, 255, 0.06)`. Holds the brand mark on the left, VRF status pill
+ language toggle + connect button on the right. Search may be inserted in
the middle for the games hub.

### Hero (landing)

Full-bleed dark panel, ~520px tall, with:
- a saturated radial spotlight in one corner using a per-game accent;
- a small "eyebrow" chip with a live-dot;
- one large display headline and a one-paragraph lede;
- two CTAs in a row: **primary** (tokamak blue, white text) + **ghost**
  (transparent, 1px white-12% border).

### Game cards (carousel + grid)

Edge-to-edge artwork is the rule. Card structure top-down:

```
┌────────────────────────────┐
│  mascot tile  (full bleed) │   220px tall, accent gradient
│                            │
├────────────────────────────┤
│  Game name        ⬢ badge  │   h3, badge upper-right
│  one-line description      │   ink-soft, 14px, max 2 lines
│  ▶ play now           →    │   tokamak blue CTA row
└────────────────────────────┘
```

- The mascot tile uses a vertical gradient from the game accent to a 30%
  darker mix toward the bottom so SVG mascots read as posters.
- On hover: card surface lifts to **PAPER-2**, mascot tile gains a 1px brand
  ring at `rgba(42, 114, 229, 0.40)`, and the arrow translates +4px.

### Buttons

- **Primary:** tokamak blue fill, `PRIMARY-I` (white) text, 1px same-color
  border. Padding `12px 22px`, weight 600, `radius-md`. Hover deepens to
  `PRIMARY-D` and gains a 6px `--glow-soft` ring.
- **Ghost:** transparent fill, 1px `rgba(255, 255, 255, 0.14)` border, white
  text. Hover background `rgba(255, 255, 255, 0.04)`.
- **Pill (small):** padding `7px 14px`, font 12.5px, used in the topbar and
  inside cards.

### Status / VRF pill

Monospace, `PAPER` background, `1px white-6%` border. A 7px dot:
- green (`SUCCESS`) — VRF live and committed (semantic green, not brand);
- amber (`WARN`) — stale beacon;
- red (`ERROR`) — RPC offline.

### Eyebrow chip

```
[ • ON-CHAIN MINI-ARCADE · L2 NATIVE ]
```

Live dot in `PRIMARY`, 12px uppercase letterform with `0.05em` tracking,
`INK-SOFT` text. The dot may carry a `box-shadow: 0 0 0 4px var(--glow)`
(blue) to read as a pulse.

### Carousel row

Section header on top:
```
SECTION KICKER ─────────────────  see all →
```

Body: `display: flex; overflow-x: auto; scroll-snap-type: x mandatory`. Each
tile is `min-width: 260px`. Scrollbars hidden; right edge fades 56px to the
canvas color.

### Final CTA panel

Dark panel at `PAPER` (subtly lifted), inset radial brand-blue glow in the
corner, two-column on desktop (text + CTA stack), one-column ≤820px. The CTA
remains `PRIMARY`.

### Footer

Dark, four-column on desktop, two-column ≤820px. Resources / Community /
Code / Brand mark + tagline. Bottom row in mono, `INK-FAINT`.

---

## Motion

- All interactive transitions: `0.15s ease` for color/border/background,
  `0.18s ease` for transform.
- Card hover: `translateY(-2px)`.
- Carousel: native scroll; no JS-driven momentum.
- Hero spotlight: optional `2.4s ease-in-out infinite alternate` on opacity
  between 0.7 and 1.0 — never on size or position (avoid layout reflow).
- Respect `prefers-reduced-motion`: disable the eyebrow pulse and hero
  spotlight breathing.

---

## Accessibility

- All text on canvas/paper meets 4.5:1 (WCAG AA). Eyeball test: pure white on
  `#131927` is ~14:1; `INK-SOFT` on the same surface is ~7:1.
- Focus rings: 2px outer offset, tokamak blue at full opacity. Never remove.
- Game card mascot tiles: the SVG mascots are decorative; the card name is
  always the accessible label. Add `aria-label` to the wrapping anchor.
- Avoid color-only signals — always pair color (win = green, loss = red) with
  text or an icon.

---

## File map

```
tokamak-arcade/
├── DESIGN.md              ← this document
├── shared/
│   ├── tokamak.css        ← all design tokens + base components
│   ├── topbar.js          ← sticky top bar
│   ├── brand.js           ← logo data URIs
│   ├── mascots.js         ← per-game SVG mascots
│   ├── lang.js            ← i18n strings
│   └── …
├── index.html             ← landing (hero + carousels + how + CTA + footer)
├── games/index.html       ← games hub (filter chips + featured + grid)
└── <game>/index.html      ← per-game pages (inherit tokens from tokamak.css)
```

---

## Building a new page

1. Link `shared/tokamak.css` and `shared/topbar.js`.
2. Mount the topbar with `mountTokamakTopbar(el, { hubHref })`.
3. Use `--tk-blue` everywhere you would have used a "primary" color — it
   resolves to the official Tokamak Network brand blue. Use `--success` (and
   `--success-glow`) only for win/live cues, never as a CTA color.
4. For new sections, prefer `tokamak-panel` for surfaces, `tokamak-card`
   for game tiles, `tokamak-btn.primary|.ghost` for actions, and the
   `section-kicker` / `eyebrow` patterns for headers.
5. Never introduce a new accent color without adding it to the per-game
   token list above. One color per game; no exceptions.

---

## What this system is *not*

- **Not a casino theme.** No red/black baize, no dice/chip clichés, no
  "WIN BIG" copy. Casino aesthetics undermine the technical credibility of
  the on-chain VRF demo — it has to read as a *gaming* platform, not a
  betting parlor.
- **Not a "playful pastel" sticker book.** The previous Base-light system
  leaned cute; this one leans *arcade-night*. Pastels survive only as
  per-game accents, and only as solid tiles, never as page backgrounds.
- **Not skeuomorphic.** No bezel, no faux-CRT, no chunky drop shadows. The
  only depth cue is a subtle background lift on hover.
