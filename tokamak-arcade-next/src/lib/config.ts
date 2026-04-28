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

export const CONFIG: ArcadeConfig = {
  chainId: Number(env.VITE_CHAIN_ID ?? 31337),
  rpc: (env.VITE_RPC_URL as string) ?? 'http://localhost:8545',
  vrfAddress: ((env.VITE_VRF_ADDRESS as Address) ??
    '0x42000000000000000000000000000000000000f0') as Address,
  flip: ((env.VITE_FLIP_ADDRESS as Address) ??
    '0x0000000000000000000000000000000000000000') as Address,
  dice: ((env.VITE_DICE_ADDRESS as Address) ??
    '0x0000000000000000000000000000000000000000') as Address,
  plinko: ((env.VITE_PLINKO_ADDRESS as Address) ??
    '0x0000000000000000000000000000000000000000') as Address,
  lottery: ((env.VITE_LOTTERY_ADDRESS as Address) ??
    '0x0000000000000000000000000000000000000000') as Address,
  jankenman: ((env.VITE_JANKENMAN_ADDRESS as Address) ??
    '0x0000000000000000000000000000000000000000') as Address
};
