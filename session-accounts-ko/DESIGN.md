## Style Prompt

Whitepaper-meets-technical-explainer. Warm cream canvas with generous breathing room. Diagrams in thin slate strokes; a single deep navy accent carries every emphasis — keywords, flow lines, attention marks. Serif display (Newsreader / Noto Serif KR) for section titles contrasts with a precise monospace (JetBrains Mono) for identifiers, keys, addresses, and code-adjacent labels. Motion is quiet: elements ease in, hold, and let the viewer read. No gradients, no glass, no glow. Think Ethereum Foundation research post or a printed cryptography paper, animated.

Shares visual system with sibling project `vrf-video-ko/` — these two videos are intended to play as a pair.

## Colors

- `#F6F3EC` — canvas (warm paper)
- `#17233A` — ink (primary text + diagram strokes)
- `#5A6472` — secondary text (captions, labels, supporting copy)
- `#1B3A8A` — accent (deep navy, used sparingly for emphasis and flow arrows)
- `#C9322B` — warning accent (only on pain points / risks, never decorative)

## Typography

- Display / body serif: `Newsreader`, `Noto Serif KR`, weights 400–600
- Mono / technical: `JetBrains Mono`, weight 400–500 for labels inside diagrams

## What NOT to Do

- No pure-white background (#FFFFFF) — always the warm cream #F6F3EC
- No gradient fills on shapes, no blur glows, no neumorphic shadows
- No bright saturated colors beyond the navy accent and the single red for risks
- No sans-serif for headlines — serif only for titles and key phrases
- No motion that bounces, overshoots, or calls attention to itself; easing is `sine.inOut`, `power2.out`, `power3.out` only
