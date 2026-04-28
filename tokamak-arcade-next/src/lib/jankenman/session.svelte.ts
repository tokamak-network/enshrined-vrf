import { createWalletClient, http, type WalletClient } from 'viem';
import {
  generatePrivateKey,
  privateKeyToAccount,
  type PrivateKeyAccount
} from 'viem/accounts';
import { browser } from '$app/environment';
import { CONFIG } from '$lib/config';
import { anvil } from '$lib/wallet.svelte';

const LS_KEY = 'janken:sessionPk';

function loadOrCreatePk(): `0x${string}` {
  if (!browser) return generatePrivateKey();
  let pk: string | null = null;
  try {
    pk = localStorage.getItem(LS_KEY);
  } catch {}
  if (!pk || !/^0x[0-9a-fA-F]{64}$/.test(pk)) {
    pk = generatePrivateKey();
    try {
      localStorage.setItem(LS_KEY, pk);
    } catch {}
  }
  return pk as `0x${string}`;
}

export type SessionKeyHandle = {
  account: PrivateKeyAccount;
  client: WalletClient;
};

let cached: SessionKeyHandle | null = null;

export function getSessionKey(): SessionKeyHandle {
  if (cached) return cached;
  const pk = loadOrCreatePk();
  const account = privateKeyToAccount(pk);
  const client = createWalletClient({
    account,
    chain: anvil,
    transport: http(CONFIG.rpc)
  });
  cached = { account, client };
  return cached;
}
