// PongMoon runtime — full game state machine + default renderer.
// Each sample provides a theme object; the runtime drives the loop.

import { createLocalEngine, HAND_EMOJI, HANDS, judge } from './engine.js';
import { SFX as DEFAULT_SFX, primeAudio } from './audio.js';

const LIGHTS = [1, 2, 4, 7, 20, 1, 2, 4, 1, 2, 7, 1, 2, 4, 1, 20];

export const DEFAULT_THEME = {
  name: 'Classic',
  palette: {
    cabinet: '#C94D3A',
    cabinetDark: '#9C3626',
    accent: '#F4D03F',
    accentDark: '#C79B1B',
    screen: '#1A1A2E',
    screenGrid: '#2A2A4E',
    win: '#F4D03F',
    lose: '#E74C3C',
    medal: '#D4A72C',
    medalDark: '#A87F1E',
    text: '#FFFFFF',
    textDim: '#6A6A8A',
    tray: '#2A2A3E',
    trayEdge: '#4A4A5E',
  },
  labels: {
    insertCoin: 'INSERT COIN',
    chant: ['짱', '깸', '뽀!'],
    win: 'WIN!',
    lose: 'LOSE',
    draw: '아이코데쇼!',
    fever: '피버!',
    prompt: '손을 선택하세요',
    playing: '확정 중...',
    idleSub: '1 CREDIT · 1 PLAY',
  },
  fonts: {
    pixel: 'monospace',
  },
  pixel: { w: 280, h: 320 },
  lights: LIGHTS,
  // hand glyph: default emoji. Overrideable per theme.
  drawHand(ctx, x, y, hand, size, theme, side) {
    ctx.save();
    ctx.font = `${size}px sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(HAND_EMOJI[hand] || '?', x, y);
    ctx.restore();
  },
  // null to use defaults
  drawBackground: null,
  drawIdle: null,
  drawChant: null,
  drawReveal: null,
  drawRoulette: null,
  drawMedalTray: null,
  drawFever: null,
  drawForeground: null,
  sfx: {},
  engineOptions: {},
};

function mergeTheme(base, override) {
  const out = { ...base, ...override };
  out.palette = { ...base.palette, ...(override.palette || {}) };
  out.labels = { ...base.labels, ...(override.labels || {}) };
  out.fonts = { ...base.fonts, ...(override.fonts || {}) };
  out.pixel = { ...base.pixel, ...(override.pixel || {}) };
  out.sfx = { ...base.sfx, ...(override.sfx || {}) };
  return out;
}

export function createGame({ canvas, theme = {}, engine = null, engineOptions = {}, hooks = {} }) {
  const t = mergeTheme(DEFAULT_THEME, theme);
  // Engine is injectable — default to LocalEngine for offline/demo mode.
  // Pass `engine: createOnChainEngine(...)` to settle rounds on the L2.
  if (!engine) engine = createLocalEngine({ ...t.engineOptions, ...engineOptions });
  const sfx = { ...DEFAULT_SFX, ...t.sfx };
  const ctx = canvas.getContext('2d');
  const W = canvas.width;
  const H = canvas.height;

  const state = {
    phase: 'IDLE',                          // IDLE | CHANT | SELECT | PLAYING | REVEAL | ROULETTE | PAYOUT | FEVER
    credits: 0,
    medals: 0,
    playerHand: null,
    machineHand: null,
    outcome: null,
    multiplier: null,
    payout: 0,
    lastResult: null,
    // timers
    idleBlink: 0,
    chaseIdx: 0,
    chaseAccum: 0,
    chantT: 0,
    chantSyllable: 0,
    revealT: 0,
    rouletteIdx: 0,
    rouletteTarget: 0,
    rouletteSpeed: 3,          // frames-per-step, grows over time
    rouletteFrame: 0,
    rouletteFlashes: 0,
    rouletteFlashT: 0,
    payoutFrame: 0,
    feverFrame: 0,
    feverFlashT: 0,
    feverFlashColor: null,
    meds: [],
    pendingDrops: 0,
    dropAccum: 0,
    dropInterval: 80,          // ms between drops
  };

  const listeners = new Set();
  const emit = () => listeners.forEach((l) => l(state));

  engine.subscribe(({ credits, medals }) => {
    state.credits = credits;
    state.medals = medals;
    emit();
  });

  function setPhase(p) {
    state.phase = p;
    if (hooks.onPhase) hooks.onPhase(p, state);
    emit();
  }

  // --- Default renderers ---
  function drawDefaultIdle() {
    const blink = Math.floor(state.idleBlink / 30) % 2 === 0;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    if (blink) {
      ctx.fillStyle = t.palette.accent;
      ctx.font = `bold 22px ${t.fonts.pixel}`;
      ctx.fillText(t.labels.insertCoin, W / 2, 180);
    }
    ctx.fillStyle = t.palette.textDim;
    ctx.font = `10px ${t.fonts.pixel}`;
    ctx.fillText(t.labels.idleSub, W / 2, 210);
  }

  function drawDefaultChant() {
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = t.palette.accent;
    ctx.font = `bold 28px ${t.fonts.pixel}`;
    const syl = t.labels.chant;
    const idx = Math.min(Math.floor(state.chantT / 220), syl.length);
    for (let i = 0; i < idx; i++) {
      ctx.fillText(syl[i], W / 2 + (i - (syl.length - 1) / 2) * 70, 170);
    }
    if (idx >= syl.length) {
      ctx.font = `10px ${t.fonts.pixel}`;
      ctx.fillStyle = t.palette.text;
      ctx.fillText(t.labels.prompt, W / 2, 210);
    }
  }

  function drawDefaultReveal() {
    const p = Math.min(1, state.revealT / 200);
    const lx = W / 2 - 70 + (1 - p) * -30;
    const rx = W / 2 + 70 + (1 - p) * 30;
    t.drawHand(ctx, lx, 170, state.playerHand, 40, t, 'player');
    t.drawHand(ctx, rx, 170, state.machineHand, 40, t, 'machine');
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = t.palette.text;
    ctx.font = `14px ${t.fonts.pixel}`;
    ctx.fillText('vs', W / 2, 170);
    if (p >= 1) {
      ctx.font = `bold 18px ${t.fonts.pixel}`;
      const label = state.outcome === 'win' ? t.labels.win
                  : state.outcome === 'lose' ? t.labels.lose : t.labels.draw;
      const color = state.outcome === 'win' ? t.palette.win
                  : state.outcome === 'lose' ? t.palette.lose : t.palette.text;
      ctx.fillStyle = color;
      ctx.fillText(label, W / 2, 220);
    }
    // impact flash
    if (p > 0.92 && p < 1.08) {
      ctx.fillStyle = 'rgba(255,255,255,0.25)';
      ctx.fillRect(0, 0, W, H);
    }
  }

  function drawRouletteRing() {
    const cx = W / 2, cy = 70, r = 48;
    for (let i = 0; i < 16; i++) {
      const a = (i / 16) * Math.PI * 2 - Math.PI / 2;
      const x = cx + Math.cos(a) * r;
      const y = cy + Math.sin(a) * r;
      let lit = false;
      if (state.phase === 'ROULETTE') lit = i === state.rouletteIdx;
      else if (state.phase === 'PAYOUT' || state.phase === 'FEVER') {
        lit = i === state.rouletteTarget && state.rouletteFlashT < 60
              ? Math.floor(state.rouletteFlashT / 12) % 2 === 0
              : i === state.rouletteTarget;
      }
      else if (state.phase === 'IDLE') lit = i === state.chaseIdx;
      ctx.fillStyle = lit ? '#FFFFFF' : '#3A2A4E';
      ctx.beginPath();
      ctx.arc(x, y, 5, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = lit ? t.palette.accent : t.palette.screenGrid;
      ctx.lineWidth = 1;
      ctx.stroke();
      ctx.fillStyle = lit ? t.palette.accent : t.palette.textDim;
      ctx.font = `8px ${t.fonts.pixel}`;
      ctx.textAlign = 'center';
      ctx.fillText(t.lights[i] + 'x', x, y + 12);
    }
    // center multiplier
    if (state.phase === 'PAYOUT' || state.phase === 'FEVER') {
      const pop = Math.min(1, state.payoutFrame / 15);
      const scale = 0.7 + pop * 0.5 - Math.max(0, (state.payoutFrame - 15) / 25) * 0.15;
      const s = Math.max(0.65, scale);
      ctx.save();
      ctx.translate(cx, cy);
      ctx.scale(s, s);
      ctx.fillStyle = t.palette.accent;
      ctx.font = `bold 20px ${t.fonts.pixel}`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText((state.multiplier || 1) + 'x', 0, 0);
      ctx.restore();
    }
  }

  function drawDefaultMedalTray() {
    const ty = H - 44;
    ctx.fillStyle = t.palette.tray;
    ctx.fillRect(10, ty, W - 20, 30);
    ctx.strokeStyle = t.palette.trayEdge;
    ctx.strokeRect(10.5, ty + 0.5, W - 21, 29);
    for (const m of state.meds) {
      ctx.fillStyle = t.palette.medal;
      ctx.beginPath(); ctx.arc(m.x, m.y, 5, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = t.palette.medalDark;
      ctx.lineWidth = 1; ctx.stroke();
      // Highlight
      ctx.beginPath();
      ctx.arc(m.x - 1.5, m.y - 1.5, 1.5, 0, Math.PI * 2);
      ctx.fillStyle = '#FDE28C';
      ctx.fill();
    }
    ctx.fillStyle = t.palette.accent;
    ctx.font = `10px ${t.fonts.pixel}`;
    ctx.textAlign = 'right';
    ctx.fillText('MEDAL × ' + state.medals, W - 16, ty + 18);
    ctx.textAlign = 'left';
    ctx.fillText('CREDIT × ' + state.credits, 16, ty + 18);
  }

  function drawMainScreen() {
    const sx = 20, sy = 140, sw = W - 40, sh = 90;
    ctx.fillStyle = '#000';
    ctx.fillRect(sx, sy, sw, sh);
    ctx.strokeStyle = t.palette.accent;
    ctx.strokeRect(sx + 0.5, sy + 0.5, sw - 1, sh - 1);
    // scanlines
    ctx.strokeStyle = 'rgba(255,255,255,0.04)';
    for (let y = sy; y < sy + sh; y += 3) {
      ctx.beginPath(); ctx.moveTo(sx, y); ctx.lineTo(sx + sw, y); ctx.stroke();
    }
  }

  function drawDefaultFever() {
    ctx.fillStyle = state.feverFlashColor || t.palette.screen;
    ctx.fillRect(0, 0, W, H);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const c = state.feverFlashColor === t.palette.accent ? t.palette.cabinet : t.palette.accent;
    ctx.fillStyle = c;
    ctx.font = `bold 38px ${t.fonts.pixel}`;
    ctx.fillText(t.labels.fever, W / 2, 90);
    ctx.font = `bold 26px ${t.fonts.pixel}`;
    ctx.fillText('20x', W / 2, 140);
  }

  function drawHandsStage() {
    // Shown during IDLE / CHANT / SELECT / PLAYING / REVEAL in wheel mode.
    // Keeps the first-screen focused on rock/scissors/paper — no wheel.
    const cx = W / 2;
    const cy = H / 2 - 20;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const ph = state.phase;

    if (ph === 'IDLE') {
      const bob = Math.sin(state.idleBlink / 18) * 4;
      ctx.font = `56px sans-serif`;
      ctx.fillText('✊', cx - 90, cy - 8 + bob);
      ctx.fillText('✌️', cx,       cy - 8 - bob);
      ctx.fillText('✋', cx + 90, cy - 8 + bob);
      if (Math.floor(state.idleBlink / 30) % 2 === 0) {
        ctx.fillStyle = t.palette.accent;
        ctx.font = `bold 20px ${t.fonts.pixel}`;
        ctx.fillText(t.labels.insertCoin || 'INSERT COIN', cx, cy + 74);
      }
      ctx.fillStyle = t.palette.textDim;
      ctx.font = `12px ${t.fonts.pixel}`;
      ctx.fillText(t.labels.idleSub || '', cx, cy + 100);
    } else if (ph === 'CHANT' || ph === 'SELECT') {
      const syl = t.labels.chant;
      const progress = state.chantT / 220;
      const shown = Math.min(Math.floor(progress) + 1, syl.length);
      ctx.fillStyle = t.palette.accent;
      ctx.font = `bold 56px ${t.fonts.pixel}`;
      for (let i = 0; i < shown; i++) {
        const alpha = i === shown - 1 ? Math.min(1, progress - i) : 1;
        ctx.globalAlpha = alpha;
        const offset = (i - (syl.length - 1) / 2) * 90;
        ctx.fillText(syl[i], cx + offset, cy);
      }
      ctx.globalAlpha = 1;
      if (ph === 'SELECT') {
        ctx.fillStyle = t.palette.text;
        ctx.font = `bold 16px ${t.fonts.pixel}`;
        ctx.fillText('↓ ' + (t.labels.prompt || '손을 골라요') + ' ↓', cx, cy + 80);
      }
    } else if (ph === 'PLAYING') {
      ctx.fillStyle = t.palette.accent;
      ctx.font = `bold 28px ${t.fonts.pixel}`;
      ctx.fillText(t.labels.playing || '...', cx, cy - 10);
      const dots = '·'.repeat((Math.floor(state.revealT / 200) % 4));
      ctx.font = `bold 36px ${t.fonts.pixel}`;
      ctx.fillText(dots, cx, cy + 30);
    } else if (ph === 'REVEAL') {
      const p = Math.min(1, state.revealT / 260);
      const spread = 110;
      ctx.font = `84px sans-serif`;
      ctx.fillText(HAND_EMOJI[state.playerHand] || '?', cx - spread * p, cy);
      ctx.fillText(HAND_EMOJI[state.machineHand] || '?', cx + spread * p, cy);
      if (p < 1) {
        ctx.fillStyle = t.palette.textDim;
        ctx.font = `bold 18px ${t.fonts.pixel}`;
        ctx.fillText('vs', cx, cy);
      }
      if (p >= 1) {
        const color = state.outcome === 'win' ? t.palette.win
                    : state.outcome === 'lose' ? t.palette.lose : t.palette.text;
        ctx.fillStyle = color;
        ctx.font = `bold 28px ${t.fonts.pixel}`;
        const label = state.outcome === 'win' ? (t.labels.win || 'WIN!')
                    : state.outcome === 'lose' ? (t.labels.lose || 'LOSE')
                    : (t.labels.draw || 'DRAW');
        ctx.fillText(label, cx, cy + 80);
      }
      // impact flash
      if (p > 0.9 && p < 1.05) {
        ctx.fillStyle = 'rgba(255,255,255,0.3)';
        ctx.fillRect(0, 0, W, H);
      }
    }
  }

  function drawArcadeWheel() {
    // Physical-cabinet style wheel — colored pie segments + Korean labels
    // + central hand character. Takes over the entire canvas when the theme
    // opts in via primaryDisplay: 'wheel'.
    const cx = W / 2;
    const cy = H / 2 - 8;
    const outerR = Math.min(W * 0.44, (H - 32) * 0.46);
    const innerR = outerR * 0.42;

    // Palette for pie wedges — theme-provided or warm arcade defaults
    const segPalette = t.wheelColors || ['#C8241A', '#E8863A', '#E8B84A', '#3576B0'];
    const darken = (hex) => {
      const n = parseInt(hex.slice(1), 16);
      const r = Math.max(0, ((n >> 16) & 0xff) - 40);
      const g = Math.max(0, ((n >> 8) & 0xff) - 40);
      const b = Math.max(0, (n & 0xff) - 40);
      return `rgb(${r},${g},${b})`;
    };

    // Determine which wedge is currently "lit" (spinning head or locked)
    function wedgeLit(i) {
      if (state.phase === 'ROULETTE') return i === state.rouletteIdx;
      if (state.phase === 'PAYOUT' || state.phase === 'FEVER') {
        if (i !== state.rouletteTarget) return false;
        const flashing = state.rouletteFlashT < 60;
        return flashing ? Math.floor(state.rouletteFlashT / 10) % 2 === 0 : true;
      }
      if (state.phase === 'IDLE') return i === state.chaseIdx;
      return false;
    }

    // Pie wedges
    for (let i = 0; i < 16; i++) {
      const a1 = (i / 16) * Math.PI * 2 - Math.PI / 2 - Math.PI / 16;
      const a2 = ((i + 1) / 16) * Math.PI * 2 - Math.PI / 2 - Math.PI / 16;
      const lit = wedgeLit(i);
      const base = segPalette[i % segPalette.length];
      ctx.fillStyle = lit ? '#FFF9E8' : base;
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.arc(cx, cy, outerR, a1, a2);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = '#0A0806';
      ctx.lineWidth = 1.5;
      ctx.stroke();

      // Number + Korean label rotated to face outward
      const midA = (a1 + a2) / 2;
      const labelR = (outerR + innerR) / 2;
      const lx = cx + Math.cos(midA) * labelR;
      const ly = cy + Math.sin(midA) * labelR;
      ctx.save();
      ctx.translate(lx, ly);
      ctx.rotate(midA + Math.PI / 2);
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      const textColor = lit ? '#0A0806' : '#FFF9E8';
      ctx.fillStyle = textColor;
      ctx.font = `bold 14px ${t.fonts.pixel}`;
      ctx.fillText(String(t.lights[i]), 0, -8);
      if (t.lightLabels) {
        ctx.font = `bold 9px ${t.fonts.pixel}`;
        ctx.fillText(t.lightLabels[i], 0, 6);
      }
      ctx.restore();
    }

    // Inner dark circle with red glow
    ctx.fillStyle = '#0A0402';
    ctx.beginPath();
    ctx.arc(cx, cy, innerR, 0, Math.PI * 2);
    ctx.fill();
    const glow = ctx.createRadialGradient(cx, cy, innerR * 0.3, cx, cy, innerR);
    glow.addColorStop(0, 'rgba(232, 50, 30, 0.5)');
    glow.addColorStop(1, 'rgba(232, 50, 30, 0)');
    ctx.fillStyle = glow;
    ctx.beginPath();
    ctx.arc(cx, cy, innerR, 0, Math.PI * 2);
    ctx.fill();

    // Outer gold bezel
    ctx.strokeStyle = t.palette.accent;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(cx, cy, outerR + 3, 0, Math.PI * 2);
    ctx.stroke();

    // CENTER CONTENT — phase-specific
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const ph = state.phase;
    if (ph === 'IDLE') {
      if (Math.floor(state.idleBlink / 30) % 2 === 0) {
        ctx.fillStyle = t.palette.accent;
        ctx.font = `bold 13px ${t.fonts.pixel}`;
        ctx.fillText('동전을', cx, cy - 10);
        ctx.fillText('넣어요', cx, cy + 8);
      }
    } else if (ph === 'CHANT' || ph === 'SELECT') {
      const syl = t.labels.chant;
      const idx = Math.min(Math.floor(state.chantT / 220), syl.length);
      ctx.fillStyle = t.palette.accent;
      ctx.font = `bold 22px ${t.fonts.pixel}`;
      if (idx > 0) ctx.fillText(syl[Math.min(idx - 1, syl.length - 1)], cx, cy);
      else ctx.fillText('?', cx, cy);
    } else if (ph === 'PLAYING') {
      ctx.fillStyle = t.palette.accent;
      ctx.font = `bold 20px ${t.fonts.pixel}`;
      const dots = '.'.repeat((Math.floor(state.revealT / 200) % 4));
      ctx.fillText(dots, cx, cy);
    } else if (ph === 'REVEAL') {
      const p = Math.min(1, state.revealT / 300);
      ctx.font = `28px sans-serif`;
      ctx.fillText(HAND_EMOJI[state.playerHand] || '?', cx - 22 * p, cy - 4);
      ctx.fillText(HAND_EMOJI[state.machineHand] || '?', cx + 22 * p, cy - 4);
      if (p >= 1) {
        ctx.font = `bold 10px ${t.fonts.pixel}`;
        const c = state.outcome === 'win' ? t.palette.win
                : state.outcome === 'lose' ? t.palette.lose : t.palette.text;
        ctx.fillStyle = c;
        const label = state.outcome === 'win' ? t.labels.win
                    : state.outcome === 'lose' ? t.labels.lose : t.labels.draw;
        ctx.fillText(label, cx, cy + 20);
      }
    } else if (ph === 'ROULETTE') {
      // Player's hand glowing red in center, pulsing
      const pulse = 0.8 + Math.sin(state.rouletteFrame * 0.3) * 0.1;
      ctx.save();
      ctx.translate(cx, cy);
      ctx.scale(pulse, pulse);
      ctx.font = `34px sans-serif`;
      ctx.fillText(HAND_EMOJI[state.playerHand] || '?', 0, 0);
      ctx.restore();
    } else if (ph === 'PAYOUT') {
      const pop = Math.min(1, state.payoutFrame / 12);
      const settle = Math.max(0, (state.payoutFrame - 12) / 20);
      const scale = Math.max(0.9, 0.5 + pop * 0.8 - settle * 0.2);
      ctx.save();
      ctx.translate(cx, cy);
      ctx.scale(scale, scale);
      ctx.fillStyle = t.palette.accent;
      ctx.font = `bold 32px ${t.fonts.pixel}`;
      ctx.fillText((state.multiplier || 1) + '×', 0, 0);
      ctx.restore();
    }

    // Bottom tag: 바위 · 가위 · 보
    ctx.fillStyle = t.palette.accent;
    ctx.font = `bold 11px ${t.fonts.pixel}`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'bottom';
    ctx.fillText('바위   가위   보', cx, H - 6);
  }

  function drawBigRoulette() {
    // Hero roulette — takes over the screen during ROULETTE/PAYOUT phases.
    const cx = W / 2;
    const cy = (H - 44) / 2;          // center above the medal tray
    const r = Math.min(W * 0.32, (H - 44) * 0.36);

    // Title strip
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = t.palette.accent;
    ctx.font = `bold 12px ${t.fonts.pixel}`;
    const headerY = Math.max(20, cy - r - 20);
    if (state.phase === 'ROULETTE') {
      ctx.fillText('★ SPINNING ★', cx, headerY);
    } else if (state.phase === 'PAYOUT') {
      ctx.fillText(t.labels.win, cx, headerY);
    }

    // Lights
    for (let i = 0; i < 16; i++) {
      const a = (i / 16) * Math.PI * 2 - Math.PI / 2;
      const x = cx + Math.cos(a) * r;
      const y = cy + Math.sin(a) * r;
      let lit = false;
      if (state.phase === 'ROULETTE') lit = i === state.rouletteIdx;
      else if (state.phase === 'PAYOUT') {
        lit = i === state.rouletteTarget && state.rouletteFlashT < 60
              ? Math.floor(state.rouletteFlashT / 12) % 2 === 0
              : i === state.rouletteTarget;
      }
      const isTarget = i === state.rouletteTarget;
      ctx.fillStyle = lit ? '#FFFFFF' : (isTarget && state.phase === 'ROULETTE' ? '#5A4A6E' : '#3A2A4E');
      ctx.beginPath();
      ctx.arc(x, y, 8, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = lit ? t.palette.accent : t.palette.screenGrid;
      ctx.lineWidth = 2;
      ctx.stroke();
      // multiplier label outside the ring
      const lx = cx + Math.cos(a) * (r + 16);
      const ly = cy + Math.sin(a) * (r + 16);
      ctx.fillStyle = lit ? t.palette.accent : t.palette.textDim;
      ctx.font = `bold 10px ${t.fonts.pixel}`;
      ctx.fillText(t.lights[i] + 'x', lx, ly);
    }

    // Big multiplier in the center
    if (state.phase === 'PAYOUT') {
      const pop = Math.min(1, state.payoutFrame / 14);
      const settle = Math.max(0, (state.payoutFrame - 14) / 26);
      const scale = Math.max(0.85, 0.6 + pop * 0.7 - settle * 0.15);
      ctx.save();
      ctx.translate(cx, cy);
      ctx.scale(scale, scale);
      ctx.fillStyle = t.palette.accent;
      ctx.font = `bold 48px ${t.fonts.pixel}`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText((state.multiplier || 1) + 'x', 0, 0);
      ctx.restore();
    } else if (state.phase === 'ROULETTE') {
      // ghost numerals teasing the target
      ctx.fillStyle = t.palette.textDim;
      ctx.font = `bold 18px ${t.fonts.pixel}`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('?', cx, cy);
    }

    // Player vs machine hand chips below the ring (small reminder)
    if (state.playerHand && state.machineHand) {
      const chipY = Math.min(H - 56, cy + r + 22);
      ctx.font = `18px sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(HAND_EMOJI[state.playerHand] || '?', cx - 30, chipY);
      ctx.fillStyle = t.palette.textDim;
      ctx.font = `bold 9px ${t.fonts.pixel}`;
      ctx.fillText('beat', cx, chipY);
      ctx.font = `18px sans-serif`;
      ctx.fillText(HAND_EMOJI[state.machineHand] || '?', cx + 30, chipY);
    }
  }

  function render() {
    // Clear to screen color
    ctx.fillStyle = t.palette.screen;
    ctx.fillRect(0, 0, W, H);
    if (t.drawBackground) t.drawBackground(ctx, W, H, state, t);

    // FEVER takes over whole screen
    if (state.phase === 'FEVER') {
      (t.drawFever || drawDefaultFever)(ctx, W, H, state, t);
    } else if (t.primaryDisplay === 'wheel') {
      // Arcade cabinet mode: hands-first screen; the wheel only appears
      // after the player wins the rock-paper-scissors match.
      if (state.phase === 'ROULETTE' || state.phase === 'PAYOUT') {
        drawArcadeWheel();
      } else {
        drawHandsStage();
      }
    } else if (state.phase === 'ROULETTE' || state.phase === 'PAYOUT') {
      // Hero roulette takes over the screen on a win
      drawBigRoulette();
    } else {
      drawRouletteRing();
      drawMainScreen();
      // Phase-specific screen contents
      const sx = 20, sy = 140, sw = W - 40, sh = 90;
      ctx.save();
      ctx.beginPath();
      ctx.rect(sx, sy, sw, sh);
      ctx.clip();
      if (state.phase === 'IDLE') (t.drawIdle || drawDefaultIdle)(ctx, W, H, state, t);
      else if (state.phase === 'CHANT' || state.phase === 'SELECT') {
        (t.drawChant || drawDefaultChant)(ctx, W, H, state, t);
      }
      else if (state.phase === 'PLAYING') {
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = t.palette.text;
        ctx.font = `10px ${t.fonts.pixel}`;
        ctx.fillText(t.labels.playing, W / 2, 185);
        const dots = '.'.repeat((Math.floor(state.revealT / 200) % 4));
        ctx.fillText(dots, W / 2, 200);
      }
      else if (state.phase === 'REVEAL') {
        (t.drawReveal || drawDefaultReveal)(ctx, W, H, state, t);
      }
      ctx.restore();
    }

    (t.drawMedalTray || drawDefaultMedalTray)(ctx, W, H, state, t);

    if (t.drawForeground) t.drawForeground(ctx, W, H, state, t);
  }

  // --- Update loop ---
  let lastT = performance.now();
  let rafId = null;

  function step(now) {
    const dt = now - lastT;
    lastT = now;

    state.idleBlink++;
    if (state.phase === 'IDLE') {
      state.chaseAccum += dt;
      if (state.chaseAccum >= 300) {
        state.chaseAccum = 0;
        state.chaseIdx = (state.chaseIdx + 1) % 16;
      }
    }
    if (state.phase === 'CHANT') {
      const prevSyllable = Math.floor(state.chantT / 220);
      state.chantT += dt;
      const newSyllable = Math.floor(state.chantT / 220);
      if (newSyllable > prevSyllable && newSyllable <= t.labels.chant.length) {
        if (sfx.tick) sfx.tick();
      }
      if (state.chantT >= t.labels.chant.length * 220 + 200) {
        setPhase('SELECT');
      }
    }
    if (state.phase === 'PLAYING' || state.phase === 'REVEAL') {
      state.revealT += dt;
    }
    if (state.phase === 'ROULETTE') {
      state.rouletteFrame++;
      state.rouletteSpeed += 0.22;
      if (state.rouletteFrame % Math.max(2, Math.round(state.rouletteSpeed)) === 0) {
        state.rouletteIdx = (state.rouletteIdx + 1) % 16;
        if (sfx.tick) sfx.tick();
      }
      if (state.rouletteSpeed >= 22 && state.rouletteIdx === state.rouletteTarget) {
        state.rouletteFlashT = 0;
        state.payoutFrame = 0;
        if (state.multiplier === 20) {
          setPhase('FEVER');
          if (sfx.fever) sfx.fever();
          if (sfx.siren) sfx.siren();
          startFeverFlash();
        } else {
          setPhase('PAYOUT');
          scheduleDrops(state.payout, 80);
          if (sfx.win) sfx.win();
        }
      }
    }
    if (state.phase === 'PAYOUT' || state.phase === 'FEVER') {
      state.rouletteFlashT += dt / 16;
      state.payoutFrame++;
    }
    if (state.phase === 'FEVER') {
      state.feverFrame++;
    }

    // Spawn scheduled medal drops
    if (state.pendingDrops > 0) {
      state.dropAccum += dt;
      while (state.dropAccum >= state.dropInterval && state.pendingDrops > 0) {
        state.dropAccum -= state.dropInterval;
        state.pendingDrops--;
        spawnMedal();
        if (sfx.medal) sfx.medal();
      }
    }

    // Physics
    for (const m of state.meds) {
      if (m.settled) continue;
      m.vy += 0.35;
      m.y += m.vy;
      if (m.y > m.ground) {
        m.y = m.ground;
        m.vy *= -0.3;
        if (Math.abs(m.vy) < 0.5) { m.vy = 0; m.settled = true; }
      }
    }

    // End-of-phase timers
    if (state.phase === 'PAYOUT' && state.payoutFrame > 180 && state.pendingDrops === 0) {
      goIdle();
    }
    if (state.phase === 'FEVER' && state.feverFrame > 420 && state.pendingDrops === 0) {
      goIdle();
    }

    // Render-skip: during IDLE the scene only changes when the blink or
    // chase index flips. Redraw on state change, otherwise reuse the last
    // frame — saves ~85% of canvas work while sitting on the menu.
    const idleDirty =
      state.phase !== 'IDLE' ||
      state.meds.length > 0 ||
      Math.floor(state.idleBlink / 30) !== lastBlink ||
      state.chaseIdx !== lastChase;
    if (idleDirty) {
      render();
      lastBlink = Math.floor(state.idleBlink / 30);
      lastChase = state.chaseIdx;
    }
    rafId = requestAnimationFrame(step);
  }
  let lastBlink = -1;
  let lastChase = -1;
  rafId = requestAnimationFrame(step);

  function startFeverFlash() {
    let toggles = 0;
    const interval = setInterval(() => {
      state.feverFlashColor = toggles % 2 === 0 ? t.palette.cabinet : t.palette.accent;
      toggles++;
      if (toggles >= 18) {
        clearInterval(interval);
        state.feverFlashColor = null;
        scheduleDrops(state.payout, 120);
      }
    }, 83);
  }

  function scheduleDrops(n, interval = 80) {
    state.pendingDrops = n;
    state.dropInterval = interval;
    state.dropAccum = 0;
  }

  function spawnMedal() {
    if (state.meds.length >= 30) state.meds.shift();
    state.meds.push({
      x: 30 + Math.random() * (W - 60),
      y: 10,
      vy: 0,
      ground: H - 28 - Math.random() * 10,
      settled: false,
    });
  }

  function goIdle() {
    setPhase('IDLE');
    state.playerHand = null;
    state.machineHand = null;
    state.outcome = null;
    state.multiplier = null;
    state.payout = 0;
    state.revealT = 0;
    state.chantT = 0;
    state.rouletteSpeed = 3;
    state.rouletteFrame = 0;
  }

  // --- Controller API ---
  async function insertCoin() {
    if (state.phase !== 'IDLE') return false;
    primeAudio();
    try { await engine.insertCoin(); } catch { return false; }
    if (sfx.coin) sfx.coin();
    state.chantT = 0;
    setPhase('CHANT');
    setTimeout(() => { if (sfx.chant) sfx.chant(); else if (sfx.jangkkaempo) sfx.jangkkaempo(); }, 150);
    return true;
  }

  async function pickHand(hand) {
    if (state.phase !== 'SELECT' && state.phase !== 'CHANT') return false;
    setPhase('PLAYING');
    if (sfx.button) sfx.button();
    let result;
    try { result = await engine.play(hand); }
    catch (e) { goIdle(); return false; }
    state.lastResult = result;
    state.playerHand = result.playerHand;
    state.machineHand = result.machineHand;
    state.outcome = result.outcome;
    state.multiplier = result.multiplier;
    state.payout = result.payout;
    state.revealT = 0;
    setPhase('REVEAL');
    if (hooks.onResult) hooks.onResult(result);

    // After short reveal pause, branch
    setTimeout(() => {
      if (state.outcome === 'win') {
        // pick a roulette light index matching the multiplier
        const matches = [];
        for (let i = 0; i < t.lights.length; i++) if (t.lights[i] === state.multiplier) matches.push(i);
        state.rouletteTarget = matches[Math.floor(Math.random() * matches.length)] ?? 0;
        state.rouletteIdx = Math.floor(Math.random() * 16);
        state.rouletteSpeed = 3;
        state.rouletteFrame = 0;
        state.rouletteFlashT = 0;
        setPhase('ROULETTE');
      } else if (state.outcome === 'lose') {
        if (sfx.lose) sfx.lose();
        setTimeout(goIdle, 1400);
      } else {
        if (sfx.draw) sfx.draw();
        setTimeout(() => setPhase('SELECT'), 1200);
      }
    }, 900);
    return true;
  }

  async function exchange() {
    const bal = await engine.getBalance();
    if (bal.medals > 0) {
      await engine.exchangeMedals(bal.medals);
      if (sfx.coin) sfx.coin();
      state.meds = [];
    }
  }

  async function reset() {
    await engine.resetBalance();
    state.meds = [];
    goIdle();
  }

  function subscribe(fn) {
    listeners.add(fn);
    fn(state);
    return () => listeners.delete(fn);
  }

  function dispose() {
    if (rafId) cancelAnimationFrame(rafId);
    listeners.clear();
  }

  return {
    state,
    theme: t,
    engine,
    insertCoin,
    pickHand,
    exchange,
    reset,
    subscribe,
    dispose,
  };
}

export { HAND_EMOJI, HANDS, judge };
