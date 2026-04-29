<script lang="ts">
  import { onMount, onDestroy } from 'svelte';

  type ResultKind = '' | 'win' | 'lose' | 'draw';

  type Props = {
    targetRotationDeg: number;
    displayEmoji: string;
    resultKind: ResultKind;
    cycling: boolean;
    selectedHand: number | null;
    onSelectHand?: (hand: number) => void;
    busy?: boolean;
  };

  let {
    targetRotationDeg = 0,
    displayEmoji = '✊',
    resultKind = '' as ResultKind,
    cycling = true,
    selectedHand = null,
    onSelectHand,
    busy = false
  }: Props = $props();

  // Wheel layout — same on-chain weighting, photo-style red/green/yellow palette
  const SEGMENTS = [
    { m: 1, color: '#3FB95F' },
    { m: 2, color: '#FFC83C' },
    { m: 1, color: '#3FB95F' },
    { m: 4, color: '#E84A4A' },
    { m: 1, color: '#3FB95F' },
    { m: 2, color: '#FFC83C' },
    { m: 7, color: '#E84A4A' },
    { m: 1, color: '#3FB95F' },
    { m: 2, color: '#FFC83C' },
    { m: 20, color: '#E84A4A' }
  ];

  // Rim labels around the wheel — position by angle from the wheel center.
  const RIM_LABELS = [
    { text: '이겼다', ang: -125, color: '#E84A4A' },
    { text: '비겼다', ang: -55, color: '#FFC83C' },
    { text: '비겼다', ang: 55, color: '#FFC83C' },
    { text: '졌다', ang: 125, color: '#E84A4A' }
  ];

  // Photo button order (left → right): 가위(red) / 바위(yellow) / 보(green).
  // hand index from contract: 0=rock, 1=paper, 2=scissors.
  const BUTTONS = [
    { idx: 2, cls: 'red', label: '가위' },
    { idx: 0, cls: 'yellow', label: '바위' },
    { idx: 1, cls: 'green', label: '보' }
  ];

  let ledCanvas: HTMLCanvasElement | null = null;
  let cycleTimer: number | null = null;

  // ─── SVG segment path ─────────────────────────────────────────────
  function segmentPath(i: number, r = 96): string {
    const a0 = ((i * 36 - 18 - 90) * Math.PI) / 180;
    const a1 = (((i + 1) * 36 - 18 - 90) * Math.PI) / 180;
    const x0 = r * Math.cos(a0);
    const y0 = r * Math.sin(a0);
    const x1 = r * Math.cos(a1);
    const y1 = r * Math.sin(a1);
    return `M 0 0 L ${x0.toFixed(2)} ${y0.toFixed(2)} A ${r} ${r} 0 0 1 ${x1.toFixed(2)} ${y1.toFixed(2)} Z`;
  }

  // ─── LED dot-matrix renderer ──────────────────────────────────────
  function drawLed() {
    if (!ledCanvas) return;
    const ctx = ledCanvas.getContext('2d')!;
    const size = ledCanvas.width;

    const ringColor =
      resultKind === 'win'
        ? '#7FE3AD'
        : resultKind === 'lose'
          ? '#FF8A8A'
          : resultKind === 'draw'
            ? '#FFE29A'
            : '#ffffff';

    // Background — recessed dark hub
    ctx.fillStyle = '#0a1a0a';
    ctx.fillRect(0, 0, size, size);

    // Render emoji into a temp mask canvas
    const tmp = document.createElement('canvas');
    tmp.width = tmp.height = size;
    const tctx = tmp.getContext('2d')!;
    tctx.font = `${Math.floor(size * 0.78)}px system-ui, "Apple Color Emoji", "Segoe UI Emoji", sans-serif`;
    tctx.textAlign = 'center';
    tctx.textBaseline = 'middle';
    tctx.fillStyle = '#ffffff';
    tctx.fillText(displayEmoji, size / 2, size / 2 + size * 0.04);
    const data = tctx.getImageData(0, 0, size, size).data;

    // Sample on a coarse grid → LED dots
    const dotSpacing = Math.max(8, Math.floor(size / 32));
    const dotRadius = dotSpacing * 0.36;
    const flicker = cycling ? Math.random() * 0.18 : 0;

    for (let y = dotSpacing / 2; y < size; y += dotSpacing) {
      for (let x = dotSpacing / 2; x < size; x += dotSpacing) {
        const idx = (Math.floor(y) * size + Math.floor(x)) * 4;
        const lit = data[idx + 3] > 70;
        if (lit) {
          ctx.beginPath();
          ctx.arc(x, y, dotRadius, 0, Math.PI * 2);
          ctx.shadowColor = ringColor;
          ctx.shadowBlur = 8;
          ctx.fillStyle = ringColor;
          ctx.globalAlpha = 1 - flicker;
          ctx.fill();
          ctx.shadowBlur = 0;
          ctx.globalAlpha = 1;
        } else {
          // Faint placeholder dots so the panel still reads as a matrix
          ctx.beginPath();
          ctx.arc(x, y, dotRadius * 0.4, 0, Math.PI * 2);
          ctx.fillStyle = 'rgba(255,255,255,0.04)';
          ctx.fill();
        }
      }
    }
  }

  function onClickButton(idx: number) {
    if (busy) return;
    onSelectHand?.(idx);
  }

  // ─── Reactivity ───────────────────────────────────────────────────
  $effect(() => {
    if (!ledCanvas) return;
    // touch the reactive deps
    void displayEmoji;
    void resultKind;
    drawLed();
  });

  $effect(() => {
    if (!ledCanvas) return;
    if (cycleTimer) {
      clearInterval(cycleTimer);
      cycleTimer = null;
    }
    if (cycling) {
      cycleTimer = window.setInterval(drawLed, 90);
    }
    return () => {
      if (cycleTimer) {
        clearInterval(cycleTimer);
        cycleTimer = null;
      }
    };
  });

  onMount(() => {
    drawLed();
  });

  onDestroy(() => {
    if (cycleTimer) clearInterval(cycleTimer);
  });
</script>

<div class="cab">
  <!-- ─── Screen ───────────────────────────────────────────────── -->
  <div class="cab-bezel">
    <div class="cab-screen">
      <h2 class="cab-title">JANKENMAN</h2>
      <span class="cab-subtitle">메달게임</span>

      <!-- Wheel + LED -->
      <div class="cab-wheel-wrap">
        <div class="cab-wheel" style="transform: rotate({targetRotationDeg}deg);">
          <svg viewBox="-100 -100 200 200" aria-hidden="true">
            <!-- Outer green ring -->
            <circle cx="0" cy="0" r="98" fill="#3FB95F" stroke="#1d7a37" stroke-width="2" />
            <!-- 10 weighted segments -->
            {#each SEGMENTS as seg, i}
              <path
                d={segmentPath(i, 92)}
                fill={seg.color}
                stroke="rgba(0,0,0,0.45)"
                stroke-width="1.2"
              />
            {/each}
            <!-- Multiplier numbers — placed at the radial midpoint of
                 each segment (inner hub r=38, outer r=92 → middle r≈64). -->
            {#each SEGMENTS as seg, i}
              <text
                x="0"
                y="-62"
                transform="rotate({i * 36 - 18} 0 0)"
                text-anchor="middle"
                dominant-baseline="middle"
                font-size="24"
                font-weight="900"
                font-family="Pretendard, system-ui, sans-serif"
                fill="#0B0F17"
                stroke="#ffffff"
                stroke-width="3.2"
                paint-order="stroke"
              >
                {seg.m}
              </text>
            {/each}
            <!-- Inner dark hub -->
            <circle
              cx="0"
              cy="0"
              r="38"
              fill="#0d2510"
              stroke="#000000"
              stroke-width="2"
            />
          </svg>
        </div>

        <!-- Korean rim labels (don't rotate) -->
        {#each RIM_LABELS as l (l.text + l.ang)}
          <span
            class="cab-rim"
            style="--ang:{l.ang}deg; color:{l.color};"
          >
            {l.text}
          </span>
        {/each}

        <!-- Pointer at top of wheel -->
        <span class="cab-pointer" aria-hidden="true"></span>

        <!-- LED display in the center -->
        <div class="cab-led">
          <canvas bind:this={ledCanvas} width="256" height="256"></canvas>
        </div>
      </div>

    </div>
  </div>

  <!-- ─── Speaker / coin panel row ────────────────────────────── -->
  <div class="cab-speakers">
    <div class="cab-speaker"></div>
    <div class="cab-strip">
      <span class="cab-strip-light"></span>
      <span class="cab-strip-light alt"></span>
    </div>
    <div class="cab-speaker"></div>
  </div>

  <!-- ─── Control deck with 3 buttons ─────────────────────────── -->
  <div class="cab-deck">
    {#each BUTTONS as b (b.idx)}
      <button
        type="button"
        class="cab-btn {b.cls}"
        class:selected={selectedHand === b.idx}
        disabled={busy}
        onclick={() => onClickButton(b.idx)}
      >
        <span class="cab-cap"></span>
        <span class="cab-label">{b.label}</span>
      </button>
    {/each}
  </div>
</div>

<style>
  /* ─── Cabinet shell ───────────────────────────────────────── */
  .cab {
    width: 100%;
    max-width: 520px;
    margin: 0 auto;
    background: linear-gradient(180deg, #d4d4cc 0%, #a8a89e 100%);
    border-radius: 14px;
    padding: 8px;
    box-shadow:
      0 24px 48px rgba(0, 0, 0, 0.45),
      0 2px 0 rgba(255, 255, 255, 0.06) inset;
  }
  .cab-bezel {
    background: #0c0c10;
    padding: 10px;
    border-radius: 8px;
    box-shadow: inset 0 0 0 2px #2a2a2a;
  }

  /* ─── Screen ──────────────────────────────────────────────── */
  .cab-screen {
    background:
      radial-gradient(1200px 600px at 30% 30%, rgba(255, 255, 255, 0.08), transparent 60%),
      linear-gradient(180deg, #3da7e6 0%, #1e6db3 100%);
    border-radius: 4px;
    aspect-ratio: 4 / 3;
    position: relative;
    overflow: hidden;
    /* CRT vignette */
    box-shadow: inset 0 0 80px rgba(0, 0, 0, 0.45);
  }
  .cab-screen::after {
    /* faint scanlines */
    content: '';
    position: absolute;
    inset: 0;
    background: repeating-linear-gradient(
      0deg,
      rgba(0, 0, 0, 0.06) 0,
      rgba(0, 0, 0, 0.06) 1px,
      transparent 1px,
      transparent 3px
    );
    pointer-events: none;
  }

  .cab-title {
    position: absolute;
    top: 14px;
    left: 18px;
    font-family: 'Pretendard', system-ui, sans-serif;
    font-weight: 900;
    font-size: clamp(20px, 4.2cqw, 32px);
    color: #ffe74e;
    -webkit-text-stroke: 2.5px #0b0f17;
    letter-spacing: -0.02em;
    line-height: 1;
    text-shadow: 2px 3px 0 rgba(0, 0, 0, 0.25);
  }
  .cab-subtitle {
    position: absolute;
    top: 22px;
    left: 36%;
    font-family: 'Pretendard', system-ui, sans-serif;
    font-weight: 700;
    font-size: clamp(11px, 1.8cqw, 14px);
    color: #ffffff;
    -webkit-text-stroke: 1px #0b0f17;
    letter-spacing: -0.01em;
  }

  /* ─── Wheel block ─────────────────────────────────────────── */
  .cab-wheel-wrap {
    position: absolute;
    left: 50%;
    top: 54%;
    width: 70%;
    aspect-ratio: 1;
    transform: translate(-50%, -50%);
  }
  .cab-wheel {
    position: absolute;
    inset: 0;
    transition: transform 3.6s cubic-bezier(0.18, 0.9, 0.24, 1);
  }
  .cab-wheel svg {
    width: 100%;
    height: 100%;
    filter: drop-shadow(0 4px 8px rgba(0, 0, 0, 0.35));
  }

  .cab-rim {
    position: absolute;
    top: 50%;
    left: 50%;
    font-family: 'Pretendard', system-ui, sans-serif;
    font-weight: 900;
    font-size: clamp(11px, 1.8cqw, 16px);
    -webkit-text-stroke: 2px #ffffff;
    letter-spacing: -0.02em;
    transform: translate(-50%, -50%) rotate(var(--ang)) translateY(-118%) rotate(calc(-1 * var(--ang)));
    pointer-events: none;
    white-space: nowrap;
  }

  .cab-pointer {
    position: absolute;
    top: -2%;
    left: 50%;
    transform: translateX(-50%);
    width: 0;
    height: 0;
    border-left: 10px solid transparent;
    border-right: 10px solid transparent;
    border-top: 18px solid #ff3333;
    filter: drop-shadow(0 2px 4px rgba(0, 0, 0, 0.4));
    z-index: 3;
  }

  .cab-led {
    position: absolute;
    inset: 30%;
    border-radius: 50%;
    background: #0a1a0a;
    overflow: hidden;
    box-shadow:
      inset 0 0 18px rgba(0, 0, 0, 0.7),
      0 0 12px rgba(127, 227, 173, 0.25);
    z-index: 2;
  }
  .cab-led canvas {
    display: block;
    width: 100%;
    height: 100%;
  }

  /* ─── Speaker / strip row ────────────────────────────────── */
  .cab-speakers {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    gap: 10px;
    padding: 14px 22px;
    background: linear-gradient(180deg, #f4f1e8 0%, #e8e3d6 100%);
    border-bottom-left-radius: 8px;
    border-bottom-right-radius: 8px;
  }
  .cab-speaker {
    width: clamp(38px, 11cqw, 52px);
    aspect-ratio: 1;
    border-radius: 50%;
    background:
      radial-gradient(circle, #1a1a1a 14%, transparent 16%) 0 0 / 7px 7px,
      radial-gradient(circle at 30% 30%, #6a6a6a, #3a3a3a 70%);
    border: 2px solid #2a2a2a;
    box-shadow:
      inset 0 2px 4px rgba(0, 0, 0, 0.4),
      0 1px 0 rgba(255, 255, 255, 0.4);
    justify-self: center;
  }
  .cab-strip {
    align-self: center;
    width: clamp(80px, 22cqw, 110px);
    height: clamp(20px, 5cqw, 26px);
    background: #2a2a2a;
    border-radius: 4px;
    border: 2px solid #1a1a1a;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 0 12px;
    box-shadow:
      inset 0 1px 2px rgba(0, 0, 0, 0.5),
      0 1px 0 rgba(255, 255, 255, 0.3);
  }
  .cab-strip-light {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: radial-gradient(circle at 30% 30%, #88ccff, #1a4488);
    box-shadow: 0 0 6px rgba(136, 204, 255, 0.7);
  }
  .cab-strip-light.alt {
    background: radial-gradient(circle at 30% 30%, #ff8888, #aa2222);
    box-shadow: 0 0 6px rgba(255, 136, 136, 0.7);
  }

  /* ─── Control deck ────────────────────────────────────────── */
  .cab-deck {
    background: linear-gradient(180deg, #ece7d8 0%, #d8d2c0 100%);
    margin-top: 8px;
    padding: 22px 16px 18px;
    border-radius: 8px;
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 12px;
    box-shadow:
      0 1px 0 rgba(255, 255, 255, 0.6) inset,
      0 -2px 4px rgba(0, 0, 0, 0.08) inset;
  }
  .cab-btn {
    appearance: none;
    background: transparent;
    border: 0;
    padding: 0;
    cursor: pointer;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    font: inherit;
  }
  .cab-btn:disabled {
    opacity: 0.55;
    cursor: not-allowed;
  }

  .cab-cap {
    width: clamp(48px, 14cqw, 72px);
    aspect-ratio: 1;
    border-radius: 50%;
    border: 3px solid #0b0f17;
    position: relative;
    box-shadow:
      0 6px 0 rgba(0, 0, 0, 0.55),
      0 8px 14px rgba(0, 0, 0, 0.25),
      inset 0 6px 12px rgba(255, 255, 255, 0.45),
      inset 0 -8px 10px rgba(0, 0, 0, 0.22);
    transition:
      transform 0.08s ease,
      box-shadow 0.08s ease,
      filter 0.15s ease;
  }
  .cab-cap::after {
    content: '';
    position: absolute;
    top: 12%;
    left: 18%;
    width: 26%;
    height: 22%;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.55);
    filter: blur(2px);
    pointer-events: none;
  }
  .cab-btn.red .cab-cap {
    background: radial-gradient(circle at 35% 30%, #ff8a7a 0%, #e84a4a 60%, #b81e1e 100%);
  }
  .cab-btn.yellow .cab-cap {
    background: radial-gradient(circle at 35% 30%, #fff0a3 0%, #ffc83c 60%, #c98e1c 100%);
  }
  .cab-btn.green .cab-cap {
    background: radial-gradient(circle at 35% 30%, #a3f0a3 0%, #3fb95f 60%, #1d7a37 100%);
  }
  .cab-btn:hover .cab-cap {
    filter: brightness(1.06);
  }
  .cab-btn:active .cab-cap,
  .cab-btn.selected .cab-cap {
    transform: translateY(4px);
    box-shadow:
      0 1px 0 rgba(0, 0, 0, 0.55),
      0 2px 4px rgba(0, 0, 0, 0.2),
      inset 0 6px 12px rgba(255, 255, 255, 0.45),
      inset 0 -4px 10px rgba(0, 0, 0, 0.22);
  }
  .cab-btn.selected .cab-cap {
    outline: 3px solid #ffe29a;
    outline-offset: 4px;
  }

  .cab-label {
    font-family: 'Pretendard', system-ui, sans-serif;
    font-weight: 800;
    font-size: clamp(13px, 2.4cqw, 16px);
    color: #0b0f17;
    -webkit-text-stroke: 0.6px rgba(255, 255, 255, 0.3);
  }

  /* ─── Container queries (so the screen contents scale) ────── */
  .cab-screen {
    container-type: inline-size;
  }
</style>
