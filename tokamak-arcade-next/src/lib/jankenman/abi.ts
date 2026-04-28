import { parseAbi } from 'viem';

export const JANKENMAN_ABI = parseAbi([
  // Play paths
  'function play(uint8 hand, uint256 bet) returns (uint8, uint8, uint8, uint256, uint256)',
  'function playFor(address owner, uint8 hand, uint256 bet) returns (uint8, uint8, uint8, uint256, uint256)',
  // Player credits
  'function credits(address) view returns (uint256)',
  'function deposit() payable',
  'function withdraw()',
  // Session keys (AA-style)
  'function startSession(address key, uint64 validUntil, uint256 gasFund) payable',
  'function setSessionKey(address key, uint64 validUntil)',
  'function revokeSession(address key)',
  'function sessionKey(address owner, address key) view returns (uint64)',
  // LP
  'function depositLP() payable',
  'function withdrawLP(uint256 shares)',
  'function lpAssets() view returns (uint256)',
  'function totalShares() view returns (uint256)',
  'function sharesOf(address) view returns (uint256)',
  // Events
  'event LPDeposited(address indexed lp, uint256 amount, uint256 sharesMinted, uint256 totalShares, uint256 lpAssets)',
  'event LPWithdrawn(address indexed lp, uint256 sharesBurned, uint256 amount, uint256 totalShares, uint256 lpAssets)',
  'event Deposited(address indexed player, uint256 amount, uint256 credits)',
  'event Withdrawn(address indexed player, uint256 amount)',
  'event SessionStarted(address indexed owner, address indexed key, uint64 validUntil, uint256 deposit, uint256 gasFund)',
  'event SessionRevoked(address indexed owner, address indexed key)',
  'event Played(address indexed player, address viaKey, uint8 playerHand, uint8 houseHand, uint8 outcome, uint8 multiplier, uint256 bet, uint256 payout, uint256 randomness)'
]);

export const VRF_ABI = parseAbi(['function commitNonce() view returns (uint256)']);

// Fixed fees for Anvil devnet — keeps every session-key tx reproducible.
export const TX_FEES = {
  maxFeePerGas: 2_000_000_000n, // 2 gwei
  maxPriorityFeePerGas: 500_000_000n, // 0.5 gwei
  gas: 500_000n
};

export const HANDS = ['✊', '✋', '✌️'] as const;
export const HAND_NAMES = ['Rock', 'Paper', 'Scissors'] as const;

export type Outcome = 0 | 1 | 2; // lose / draw / win

// Multiplier weights — mirror the on-chain table for preview math.
export const MULTS = [
  { m: 1, p: 70 },
  { m: 2, p: 18 },
  { m: 4, p: 8 },
  { m: 7, p: 3 },
  { m: 20, p: 1 }
] as const;

export const WHEEL_SEGMENTS = [
  { m: 1, color: 'sky' },
  { m: 2, color: 'mint' },
  { m: 1, color: 'sky' },
  { m: 4, color: 'butter' },
  { m: 1, color: 'sky' },
  { m: 2, color: 'mint' },
  { m: 7, color: 'lavender' },
  { m: 1, color: 'sky' },
  { m: 2, color: 'mint' },
  { m: 20, color: 'coral' }
] as const;
