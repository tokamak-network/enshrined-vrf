import type { Address } from 'viem';

export interface ArcadeConfig {
  chainId: number;
  rpc: string;
  vrfAddress: Address;
  flip: Address;
  dice: Address;
  plinko: Address;
  lottery: Address;
  jankenman: Address;
}

const env = import.meta.env;

// Defaults match the deterministic Anvil deployment that
// scripts/arcade.sh in the legacy repo writes to
// arcade/shared/config.js — same default mnemonic + sequential nonces.
// Override with VITE_*_ADDRESS env vars when deploying elsewhere.
const DEFAULTS = {
  chainId: 31337,
  rpc: 'http://localhost:8545',
  vrfAddress: '0x42000000000000000000000000000000000000f0',
  flip: '0x5FbDB2315678afecb367f032d93F642f64180aa3',
  dice: '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512',
  plinko: '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
  lottery: '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9',
  jankenman: '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9'
} as const;

export const CONFIG: ArcadeConfig = {
  chainId: Number(env.VITE_CHAIN_ID ?? DEFAULTS.chainId),
  rpc: (env.VITE_RPC_URL as string) ?? DEFAULTS.rpc,
  vrfAddress: ((env.VITE_VRF_ADDRESS as Address) ?? DEFAULTS.vrfAddress) as Address,
  flip: ((env.VITE_FLIP_ADDRESS as Address) ?? DEFAULTS.flip) as Address,
  dice: ((env.VITE_DICE_ADDRESS as Address) ?? DEFAULTS.dice) as Address,
  plinko: ((env.VITE_PLINKO_ADDRESS as Address) ?? DEFAULTS.plinko) as Address,
  lottery: ((env.VITE_LOTTERY_ADDRESS as Address) ?? DEFAULTS.lottery) as Address,
  jankenman: ((env.VITE_JANKENMAN_ADDRESS as Address) ?? DEFAULTS.jankenman) as Address
};
