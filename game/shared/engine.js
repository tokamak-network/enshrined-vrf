// PongMoon — Shared GameEngine (LocalGameEngine)
// Every sample imports this to keep randomness, payout, and balance logic
// behind a single interface (PRD §5.2). VRF swap later = new implementation only.

export const HANDS = ['rock', 'scissors', 'paper'];

export const HAND_EMOJI = {
  rock: '✊',
  scissors: '✌️',
  paper: '✋',
};

export const GAME_CONFIG = {
  startingCredits: 10,
  coinCost: 1,
  maxConsecutiveDraws: 3,
  handSelectTimeoutMs: 5000,
  artificialLatencyMs: { min: 1500, max: 2500 },
  roulette: [
    { multiplier: 1,  weight: 50 },
    { multiplier: 2,  weight: 25 },
    { multiplier: 4,  weight: 15 },
    { multiplier: 7,  weight: 8  },
    { multiplier: 20, weight: 2  },
  ],
};

export function judge(playerHand, machineHand) {
  if (playerHand === machineHand) return 'draw';
  const beats = { rock: 'scissors', scissors: 'paper', paper: 'rock' };
  return beats[playerHand] === machineHand ? 'win' : 'lose';
}

function pickWeighted(entries, rng = Math.random) {
  const total = entries.reduce((s, e) => s + e.weight, 0);
  let r = rng() * total;
  for (const e of entries) {
    if ((r -= e.weight) <= 0) return e;
  }
  return entries[entries.length - 1];
}

function randomHand(rng = Math.random) {
  return HANDS[Math.floor(rng() * 3)];
}

function shortId() {
  return (Date.now().toString(36) + Math.random().toString(36).slice(2, 8)).toUpperCase();
}

function delay(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

export function createLocalEngine(overrides = {}) {
  const cfg = { ...GAME_CONFIG, ...overrides };
  const listeners = new Set();
  const state = {
    credits: cfg.startingCredits,
    medals: 0,
    consecutiveDraws: 0,
    history: [],
  };

  const emit = () => {
    const snap = { credits: state.credits, medals: state.medals };
    listeners.forEach((l) => l(snap));
  };

  return {
    async getBalance() {
      return { credits: state.credits, medals: state.medals };
    },

    async insertCoin() {
      if (state.credits < cfg.coinCost) throw new Error('INSUFFICIENT_CREDITS');
      state.credits -= cfg.coinCost;
      emit();
      return { credits: state.credits, medals: state.medals };
    },

    async play(playerHand) {
      const min = cfg.artificialLatencyMs.min;
      const max = cfg.artificialLatencyMs.max;
      await delay(min + Math.random() * (max - min));

      let machineHand = randomHand();
      let outcome = judge(playerHand, machineHand);

      if (outcome === 'draw') {
        state.consecutiveDraws += 1;
        if (state.consecutiveDraws > cfg.maxConsecutiveDraws) {
          const beats = { rock: 'scissors', scissors: 'paper', paper: 'rock' };
          machineHand = Object.keys(beats).find((k) => beats[k] === playerHand);
          outcome = 'lose';
          state.consecutiveDraws = 0;
        }
      } else {
        state.consecutiveDraws = 0;
      }

      let multiplier = null;
      let payout = 0;
      if (outcome === 'win') {
        const pick = pickWeighted(cfg.roulette);
        multiplier = pick.multiplier;
        payout = multiplier * cfg.coinCost;
        state.medals += payout;
      }

      const result = {
        playerHand,
        machineHand,
        outcome,
        multiplier,
        payout,
        rngSeed: shortId(),
        roundId: shortId(),
      };
      state.history.push(result);
      emit();
      return result;
    },

    async exchangeMedals(count) {
      const n = Math.min(count, state.medals);
      state.medals -= n;
      state.credits += n;
      emit();
      return { credits: state.credits, medals: state.medals };
    },

    async resetBalance() {
      state.credits = cfg.startingCredits;
      state.medals = 0;
      state.consecutiveDraws = 0;
      state.history = [];
      emit();
      return { credits: state.credits, medals: state.medals };
    },

    getHistory() {
      return state.history.slice();
    },

    subscribe(listener) {
      listeners.add(listener);
      listener({ credits: state.credits, medals: state.medals });
      return () => listeners.delete(listener);
    },
  };
}
