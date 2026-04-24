// On-chain GameEngine adapter for PongyBet.sol.
// Matches the GameEngine interface in engine.js so the existing runtime/UI
// keeps working — only the engine swaps. Uses viem (loaded from ESM CDN).

import {
  createPublicClient,
  createWalletClient,
  custom,
  http,
  parseAbi,
  parseAbiItem,
  parseUnits,
  formatUnits,
  getAddress,
} from 'https://esm.sh/viem@2.21.0';

const PONGYBET_ABI = parseAbi([
  'function deposit(uint256 amount)',
  'function withdraw()',
  'function play(uint8 hand) returns (uint8, uint8, uint8, uint256, uint256)',
  'function credits(address) view returns (uint256)',
  'function medals(address) view returns (uint256)',
  'function balanceOf(address) view returns (uint256, uint256)',
  'event Played(address indexed player, uint8 playerHand, uint8 machineHand, uint8 outcome, uint8 multiplier, uint256 payout, uint256 randomness)',
  'event Deposited(address indexed player, uint256 amount)',
  'event Withdrawn(address indexed player, uint256 amount)',
]);

const ERC20_ABI = parseAbi([
  'function approve(address spender, uint256 amount) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)',
  'function balanceOf(address) view returns (uint256)',
]);

const HAND_TO_ENUM = { rock: 0, scissors: 1, paper: 2 };
const ENUM_TO_HAND = ['rock', 'scissors', 'paper'];
const OUTCOME = ['lose', 'draw', 'win'];

const BET = 1_000_000n; // 1 USDC (6 decimals)

/**
 * Create an on-chain game engine.
 *
 * @param {object} opts
 * @param {string} opts.chainRpc           — JSON-RPC URL of the Enshrined-VRF L2
 * @param {`0x${string}`} opts.gameAddress — deployed PongyBet contract
 * @param {`0x${string}`} opts.usdcAddress — USDC on the L2
 * @param {object}       opts.wallet       — EIP-1193 provider (window.ethereum)
 * @param {bigint}       [opts.depositAmount=10n * BET]
 */
export async function createOnChainEngine({
  chainRpc,
  gameAddress,
  usdcAddress,
  wallet,
  depositAmount = 10n * BET,
}) {
  gameAddress = getAddress(gameAddress);
  usdcAddress = getAddress(usdcAddress);

  const pub = createPublicClient({ transport: http(chainRpc) });
  const w = createWalletClient({ transport: custom(wallet) });
  const [account] = await w.requestAddresses();

  const listeners = new Set();
  // Cached balance in smallest units (bigint). Updated in-place from events
  // after tx receipts — avoids a per-tx RPC roundtrip.
  let cachedCredits = 0n;
  let cachedMedals  = 0n;

  async function fetchBalance() {
    const [c, m] = await pub.readContract({
      address: gameAddress, abi: PONGYBET_ABI, functionName: 'balanceOf', args: [account],
    });
    cachedCredits = c; cachedMedals = m;
    return snap();
  }

  function snap() {
    return { credits: Number(cachedCredits / BET), medals: Number(cachedMedals / BET) };
  }

  function emit() {
    const s = snap();
    listeners.forEach((l) => l(s));
  }

  // Single watcher on the contract — filter by our player and fan out by event.
  // Viem requires one watch per event name, but we share the same refresh path
  // (`fetchBalance`) and only hit the RPC when our own events land.
  const EVENTS = ['Played', 'Deposited', 'Withdrawn'];
  for (const name of EVENTS) {
    pub.watchContractEvent({
      address: gameAddress, abi: PONGYBET_ABI, eventName: name,
      args: { player: account },
      onLogs: () => fetchBalance().then(emit),
    });
  }

  async function ensureAllowance(amount) {
    const cur = await pub.readContract({
      address: usdcAddress, abi: ERC20_ABI, functionName: 'allowance',
      args: [account, gameAddress],
    });
    if (cur >= amount) return;
    const hash = await w.writeContract({
      account, chain: null,
      address: usdcAddress, abi: ERC20_ABI, functionName: 'approve',
      args: [gameAddress, amount],
    });
    await pub.waitForTransactionReceipt({ hash });
  }

  async function getBalance() { return fetchBalance(); }

  async function insertCoin() {
    // First-time: top up credits on-chain if bankroll is empty.
    const bal = await fetchBalance();
    if (bal.credits < 1) {
      await ensureAllowance(depositAmount);
      const hash = await w.writeContract({
        account, chain: null,
        address: gameAddress, abi: PONGYBET_ABI, functionName: 'deposit',
        args: [depositAmount],
      });
      await pub.waitForTransactionReceipt({ hash });
    }
    // "insertCoin" is a UI-only step — the real debit happens inside play().
    return fetchBalance();
  }

  // Decode Played event once — viem parses topics against the ABI.
  const PLAYED_ITEM = parseAbiItem(
    'event Played(address indexed player, uint8 playerHand, uint8 machineHand, uint8 outcome, uint8 multiplier, uint256 payout, uint256 randomness)'
  );
  const PLAYED_SIG = PLAYED_ITEM; // for decodeEventLog

  async function play(handName) {
    const hand = HAND_TO_ENUM[handName];
    if (hand === undefined) throw new Error('bad hand');
    const hash = await w.writeContract({
      account, chain: null,
      address: gameAddress, abi: PONGYBET_ABI, functionName: 'play',
      args: [hand],
    });
    const receipt = await pub.waitForTransactionReceipt({ hash });

    // Find OUR Played log in the receipt without a second RPC.
    const gameAddrLc = gameAddress.toLowerCase();
    let args;
    for (let i = 0; i < receipt.logs.length; i++) {
      const l = receipt.logs[i];
      if (l.address.toLowerCase() !== gameAddrLc) continue;
      try {
        const dec = pub.decodeEventLog({ abi: [PLAYED_SIG], data: l.data, topics: l.topics });
        if (dec.eventName === 'Played') { args = dec.args; break; }
      } catch { /* not ours */ }
    }
    if (!args) throw new Error('Played event not found');

    // Apply balance delta locally — saves one eth_call on the return path.
    const outcomeIdx = Number(args.outcome);
    if (outcomeIdx === 1) {
      // draw: no change (contract skipped the debit entirely)
    } else {
      cachedCredits -= BET;
      if (outcomeIdx === 2) cachedMedals += args.payout;
    }
    emit();

    return {
      playerHand: handName,
      machineHand: ENUM_TO_HAND[Number(args.machineHand)],
      outcome: OUTCOME[outcomeIdx],
      multiplier: outcomeIdx === 2 ? Number(args.multiplier) : null,
      payout: Number(args.payout) / Number(BET),
      // VRF beta serves directly as the rngSeed — verifiable on-chain.
      rngSeed: '0x' + args.randomness.toString(16).padStart(64, '0'),
      roundId: hash,
    };
  }

  async function exchangeMedals(/* count */) {
    // On-chain: medals map 1:1 to USDC — withdraw all in one tx.
    const hash = await w.writeContract({
      account, chain: null,
      address: gameAddress, abi: PONGYBET_ABI, functionName: 'withdraw',
      args: [],
    });
    await pub.waitForTransactionReceipt({ hash });
    return fetchBalance();
  }

  async function resetBalance() {
    // No-op on-chain: balances are real USDC. Leave it to the UI to refresh.
    return fetchBalance();
  }

  function subscribe(fn) {
    listeners.add(fn);
    fetchBalance().then(fn).catch(() => fn({ credits: 0, medals: 0 }));
    return () => listeners.delete(fn);
  }

  return {
    account,
    getBalance, insertCoin, play, exchangeMedals, resetBalance, subscribe,
  };
}
