// Shared arcade chiptune audio — 8-bit style, synthesized (no external files).
// Browser autoplay-policy safe: AudioContext only resumes after first gesture.

let ctx = null;
let muted = false;
let masterGain = null;
let bgmGain = null;
let bgmActive = false;
let bgmTimer = null;
let duckUntil = 0;

function ensureCtx() {
  if (!ctx) {
    const Ctor = window.AudioContext || window.webkitAudioContext;
    if (!Ctor) return null;
    ctx = new Ctor();
    masterGain = ctx.createGain();
    masterGain.gain.value = 1;
    masterGain.connect(ctx.destination);
  }
  if (ctx.state === 'suspended') ctx.resume();
  return ctx;
}

export function setMuted(v) {
  muted = !!v;
  if (masterGain) masterGain.gain.value = muted ? 0 : 1;
}

// Duck BGM briefly when important SFX plays (30% per PRD §6.2)
function duck(durationMs = 260) {
  duckUntil = Math.max(duckUntil, (ctx ? ctx.currentTime : 0) + durationMs / 1000);
  if (!bgmGain || !ctx) return;
  const now = ctx.currentTime;
  bgmGain.gain.cancelScheduledValues(now);
  bgmGain.gain.setValueAtTime(bgmGain.gain.value, now);
  bgmGain.gain.linearRampToValueAtTime(0.014, now + 0.04);
  bgmGain.gain.setValueAtTime(0.014, now + durationMs / 1000 - 0.04);
  bgmGain.gain.linearRampToValueAtTime(0.045, now + durationMs / 1000 + 0.12);
}

// ──────────────────────────────────────────
// Note frequencies (equal temperament)
// ──────────────────────────────────────────
const N = {
  C3: 130.81, D3: 146.83, E3: 164.81, F3: 174.61, G3: 196.00, A3: 220.00, B3: 246.94,
  C4: 261.63, D4: 293.66, E4: 329.63, F4: 349.23, G4: 392.00, A4: 440.00, B4: 493.88,
  C5: 523.25, D5: 587.33, Eb5: 622.25, E5: 659.25, F5: 698.46, G5: 783.99, A5: 880.00, B5: 987.77,
  C6: 1046.50, D6: 1174.66, E6: 1318.51, F6: 1396.91, G6: 1567.98, A6: 1760.00, B6: 1975.53,
  C7: 2093.00, E7: 2637.02,
};

// ──────────────────────────────────────────
// Primitives
// ──────────────────────────────────────────
function blip(freq, dur = 0.07, type = 'square', gain = 0.12, delay = 0) {
  const c = ensureCtx(); if (!c || muted) return;
  const t0 = c.currentTime + delay;
  const osc = c.createOscillator();
  const g = c.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(freq, t0);
  g.gain.setValueAtTime(0.0001, t0);
  g.gain.linearRampToValueAtTime(gain, t0 + 0.003);
  g.gain.setValueAtTime(gain, t0 + Math.max(0, dur - 0.03));
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
  osc.connect(g).connect(masterGain);
  osc.start(t0);
  osc.stop(t0 + dur + 0.02);
}

function sweep(f1, f2, dur, type = 'square', gain = 0.12, delay = 0) {
  const c = ensureCtx(); if (!c || muted) return;
  const t0 = c.currentTime + delay;
  const osc = c.createOscillator();
  const g = c.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(f1, t0);
  osc.frequency.exponentialRampToValueAtTime(Math.max(20, f2), t0 + dur);
  g.gain.setValueAtTime(0.0001, t0);
  g.gain.linearRampToValueAtTime(gain, t0 + 0.005);
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
  osc.connect(g).connect(masterGain);
  osc.start(t0);
  osc.stop(t0 + dur + 0.02);
}

function noise(dur = 0.06, gain = 0.1, hp = 3000, delay = 0) {
  const c = ensureCtx(); if (!c || muted) return;
  const t0 = c.currentTime + delay;
  const buf = c.createBuffer(1, Math.floor(c.sampleRate * dur), c.sampleRate);
  const d = buf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  const src = c.createBufferSource();
  src.buffer = buf;
  const g = c.createGain();
  g.gain.setValueAtTime(gain, t0);
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
  const filter = c.createBiquadFilter();
  filter.type = 'highpass';
  filter.frequency.value = hp;
  src.connect(filter).connect(g).connect(masterGain);
  src.start(t0);
  src.stop(t0 + dur + 0.02);
}

// Arpeggio helper — plays a sequence of notes with equal spacing
function arp(freqs, stepMs = 80, dur = 0.08, type = 'square', gain = 0.13) {
  freqs.forEach((f, i) => blip(f, dur, type, gain, (i * stepMs) / 1000));
}

// ──────────────────────────────────────────
// SFX — classic arcade 8-bit flavor
// ──────────────────────────────────────────
export const SFX = {
  // Coin drop → metallic rising blip + sparkle noise
  coin: () => {
    duck(200);
    blip(N.A5,  0.05, 'square', 0.13, 0.00);
    blip(N.E6,  0.05, 'square', 0.13, 0.05);
    blip(N.A6,  0.09, 'square', 0.12, 0.10);
    noise(0.05, 0.06, 5000, 0.12);
  },

  // Arcade pushbutton "tok"
  button: () => {
    blip(N.C6,  0.035, 'square',   0.13);
    blip(N.E5,  0.020, 'triangle', 0.08, 0.01);
  },

  // Roulette light tick — short high chirp
  tick: () => {
    blip(2600, 0.022, 'square', 0.07);
  },

  // Medal drops into tray — metallic clink
  medal: () => {
    blip(N.E6, 0.03, 'triangle', 0.10, 0.00);
    blip(N.B6, 0.05, 'triangle', 0.09, 0.02);
    noise(0.025, 0.04, 6000, 0.015);
  },

  // Win — Mario-style major arpeggio
  win: () => {
    duck(500);
    arp([N.C5, N.E5, N.G5], 70, 0.075, 'square', 0.13);
    blip(N.C6, 0.22, 'square', 0.15, 0.21);
    // tiny sparkle on top
    blip(N.E6, 0.1, 'triangle', 0.08, 0.33);
  },

  // Lose — descending "sad trombone"
  lose: () => {
    duck(600);
    blip(N.E4, 0.14, 'sawtooth', 0.11, 0.00);
    blip(N.D4, 0.14, 'sawtooth', 0.11, 0.14);
    blip(N.C4, 0.14, 'sawtooth', 0.11, 0.28);
    sweep(N.C4, N.G3, 0.35, 'sawtooth', 0.10, 0.42);
  },

  // Draw — two neutral beeps
  draw: () => {
    blip(N.G4, 0.09, 'square', 0.10, 0.00);
    blip(N.G4, 0.09, 'square', 0.10, 0.16);
  },

  // "짱-깸-뽀!" three rising chant notes
  jangkkaempo: () => {
    blip(N.C5, 0.14, 'square', 0.13, 0.00);
    blip(N.E5, 0.14, 'square', 0.13, 0.22);
    blip(N.G5, 0.22, 'square', 0.15, 0.44);
  },

  // FEVER jackpot fanfare
  fever: () => {
    duck(900);
    arp([N.C5, N.G5, N.C6, N.E6, N.G6, N.C7], 95, 0.095, 'square', 0.14);
    blip(N.E7, 0.3, 'triangle', 0.10, 0.60);
    // shimmer tail
    for (let i = 0; i < 8; i++) blip(N.C7 + (Math.random() - 0.5) * 400, 0.04, 'triangle', 0.06, 0.70 + i * 0.05);
  },

  // Warbling siren — used alongside fever
  siren: () => {
    sweep(600, 1200, 0.30, 'sine', 0.08, 0.0);
    sweep(1200, 600, 0.30, 'sine', 0.08, 0.3);
    sweep(600, 1200, 0.30, 'sine', 0.08, 0.6);
    sweep(1200, 600, 0.30, 'sine', 0.08, 0.9);
  },
};

// ──────────────────────────────────────────
// BGM — optional looping chiptune melody (idle)
// ──────────────────────────────────────────
// Simple 8-bar melody in C major, plus a simple bass line.
const BGM_MELODY = [
  // bar 1-2
  ['C5', 0.22], ['E5', 0.22], ['G5', 0.22], ['E5', 0.22],
  ['C5', 0.22], ['E5', 0.22], ['G5', 0.22], ['A5', 0.22],
  // bar 3-4
  ['G5', 0.22], ['E5', 0.22], ['C5', 0.22], ['D5', 0.22],
  ['E5', 0.44], ['G5', 0.44],
  // bar 5-6
  ['A5', 0.22], ['G5', 0.22], ['E5', 0.22], ['C5', 0.22],
  ['D5', 0.22], ['E5', 0.22], ['D5', 0.22], ['C5', 0.22],
  // bar 7-8
  ['G4', 0.22], ['C5', 0.22], ['E5', 0.22], ['G5', 0.22],
  ['C6', 0.44], ['REST', 0.44],
];
const BGM_BASS = [
  ['C3', 0.44], ['C3', 0.44], ['C3', 0.44], ['C3', 0.44],
  ['G3', 0.44], ['G3', 0.44], ['C3', 0.44], ['G3', 0.44],
  ['A3', 0.44], ['A3', 0.44], ['F3', 0.44], ['G3', 0.44],
  ['C3', 0.44], ['C3', 0.44], ['G3', 0.44], ['C3', 0.44],
];

function playBgmBar() {
  const c = ensureCtx(); if (!c || !bgmActive) return;
  let tMel = c.currentTime + 0.02;
  for (const [n, d] of BGM_MELODY) {
    if (n !== 'REST') {
      const f = N[n];
      const osc = c.createOscillator();
      const g = c.createGain();
      osc.type = 'square';
      osc.frequency.setValueAtTime(f, tMel);
      g.gain.setValueAtTime(0, tMel);
      g.gain.linearRampToValueAtTime(0.045, tMel + 0.008);
      g.gain.setValueAtTime(0.045, tMel + Math.max(0, d - 0.04));
      g.gain.exponentialRampToValueAtTime(0.0001, tMel + d);
      osc.connect(g).connect(bgmGain);
      osc.start(tMel);
      osc.stop(tMel + d + 0.01);
    }
    tMel += d;
  }
  // Bass line
  let tBass = c.currentTime + 0.02;
  for (const [n, d] of BGM_BASS) {
    const f = N[n];
    const osc = c.createOscillator();
    const g = c.createGain();
    osc.type = 'triangle';
    osc.frequency.setValueAtTime(f, tBass);
    g.gain.setValueAtTime(0, tBass);
    g.gain.linearRampToValueAtTime(0.04, tBass + 0.01);
    g.gain.setValueAtTime(0.04, tBass + d - 0.06);
    g.gain.exponentialRampToValueAtTime(0.0001, tBass + d);
    osc.connect(g).connect(bgmGain);
    osc.start(tBass);
    osc.stop(tBass + d + 0.01);
    tBass += d;
  }
  const barLen = BGM_MELODY.reduce((s, [, d]) => s + d, 0);
  bgmTimer = setTimeout(playBgmBar, barLen * 1000);
}

export function startBgm() {
  const c = ensureCtx(); if (!c || muted || bgmActive) return;
  bgmActive = true;
  bgmGain = c.createGain();
  bgmGain.gain.value = 0.045;
  bgmGain.connect(masterGain);
  playBgmBar();
}

export function stopBgm() {
  bgmActive = false;
  if (bgmTimer) { clearTimeout(bgmTimer); bgmTimer = null; }
  if (bgmGain && ctx) {
    bgmGain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.3);
    const dead = bgmGain;
    setTimeout(() => { try { dead.disconnect(); } catch {} }, 400);
    bgmGain = null;
  }
}

export function primeAudio() { ensureCtx(); }
