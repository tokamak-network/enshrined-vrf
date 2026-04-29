import {
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  getAddress,
  http,
  type Address,
  type Chain,
  type PublicClient,
  type WalletClient
} from 'viem';
import { browser } from '$app/environment';
import { createStore, type EIP1193Provider, type Store } from 'mipd';
import { CONFIG } from './config';

export const anvil: Chain = defineChain({
  id: CONFIG.chainId,
  name: 'Enshrined VRF Devnet',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: [CONFIG.rpc] } }
});

export const pub: PublicClient = createPublicClient({
  chain: anvil,
  transport: http(CONFIG.rpc)
});

const CHAIN_HEX = '0x' + CONFIG.chainId.toString(16);

const PREFERRED_RDNS = ['io.metamask', 'io.metamask.flask'];

const mipdStore: Store | null = browser ? createStore() : null;

const LS_INTENT_KEY = 'tokamak:wallet:intent';
type Intent = 'connected' | 'disconnected';

function getIntent(): Intent | null {
  if (!browser) return null;
  try {
    const v = localStorage.getItem(LS_INTENT_KEY);
    return v === 'connected' || v === 'disconnected' ? v : null;
  } catch {
    return null;
  }
}

function setIntent(v: Intent) {
  if (!browser) return;
  try {
    localStorage.setItem(LS_INTENT_KEY, v);
  } catch {}
}

function pickProvider(): EIP1193Provider | null {
  if (!browser) return null;

  const announced = mipdStore?.getProviders() ?? [];
  if (announced.length > 0) {
    for (const rdns of PREFERRED_RDNS) {
      const hit = announced.find((p) => p.info.rdns === rdns);
      if (hit) return hit.provider;
    }
    return announced[0].provider;
  }

  const eth = (window as unknown as { ethereum?: EIP1193Provider & { providers?: EIP1193Provider[] } }).ethereum;
  if (!eth) return null;

  if (Array.isArray(eth.providers) && eth.providers.length > 0) {
    const mm = eth.providers.find((p) => (p as unknown as { isMetaMask?: boolean }).isMetaMask);
    return mm ?? eth.providers[0];
  }
  return eth;
}

function providerName(p: EIP1193Provider): string | null {
  const detail = mipdStore?.getProviders().find((d) => d.provider === p);
  return detail?.info.name ?? null;
}

function createWallet() {
  let account = $state<Address | null>(null);
  let walletClient = $state<WalletClient | null>(null);
  let activeProvider = $state<EIP1193Provider | null>(null);
  let walletName = $state<string | null>(null);
  let connecting = $state(false);
  let error = $state<string | null>(null);

  async function currentChainId(p: EIP1193Provider): Promise<string> {
    return (await p.request({ method: 'eth_chainId' })) as string;
  }

  async function ensureOnDevnet(p: EIP1193Provider) {
    if ((await currentChainId(p)).toLowerCase() === CHAIN_HEX) return;

    try {
      await p.request({
        method: 'wallet_addEthereumChain',
        params: [
          {
            chainId: CHAIN_HEX,
            chainName: anvil.name,
            rpcUrls: [CONFIG.rpc],
            nativeCurrency: anvil.nativeCurrency
          }
        ]
      });
    } catch (err) {
      const e = err as { code?: number };
      if (e?.code === 4001) throw err;
      await p.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: CHAIN_HEX }]
      });
    }

    if ((await currentChainId(p)).toLowerCase() !== CHAIN_HEX) {
      await p.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: CHAIN_HEX }]
      });
    }
    if ((await currentChainId(p)).toLowerCase() !== CHAIN_HEX) {
      throw new Error(
        `Wallet did not switch to devnet (chainId ${CONFIG.chainId}). ` +
          `Please pick "${anvil.name}" from the network list manually.`
      );
    }
  }

  function attachProviderListeners(p: EIP1193Provider) {
    p.on?.('chainChanged', () => window.location.reload());
    p.on?.('accountsChanged', (newAccounts: unknown) => {
      if (!Array.isArray(newAccounts) || newAccounts.length === 0) {
        setIntent('disconnected');
      }
      window.location.reload();
    });
  }

  async function connect() {
    if (!browser) throw new Error('Cannot connect on the server.');
    const picked = pickProvider();
    if (!picked) throw new Error('Install MetaMask to play.');

    if (mipdStore) {
      const announced = mipdStore.getProviders();
      console.log(
        '[wallet] EIP-6963 announced:',
        announced.map((d) => `${d.info.name} (${d.info.rdns})`)
      );
    }
    console.log('[wallet] picked provider:', providerName(picked) ?? '(legacy window.ethereum)');

    connecting = true;
    error = null;
    try {
      await ensureOnDevnet(picked);
      const wc = createWalletClient({
        chain: anvil,
        transport: custom(picked)
      });
      const accounts = await wc.requestAddresses();
      activeProvider = picked;
      walletClient = wc;
      account = getAddress(accounts[0]);
      walletName = providerName(picked);
      setIntent('connected');

      attachProviderListeners(picked);
      return account;
    } catch (err) {
      const e = err as { message?: string };
      error = e?.message ?? String(err);
      throw err;
    } finally {
      connecting = false;
    }
  }

  async function restore() {
    if (!browser) return;
    if (account) return;
    if (getIntent() !== 'connected') return;
    const picked = pickProvider();
    if (!picked) return;
    try {
      const accounts = (await picked.request({ method: 'eth_accounts' })) as string[];
      if (!Array.isArray(accounts) || accounts.length === 0) {
        setIntent('disconnected');
        return;
      }
      const wc = createWalletClient({
        chain: anvil,
        transport: custom(picked)
      });
      activeProvider = picked;
      walletClient = wc;
      account = getAddress(accounts[0]);
      walletName = providerName(picked);
      attachProviderListeners(picked);
    } catch (err) {
      console.warn('[wallet] silent restore failed', err);
    }
  }

  async function ensureChain() {
    const p = activeProvider;
    if (!p) throw new Error('Wallet not connected.');
    await ensureOnDevnet(p);
  }

  return {
    get account() {
      return account;
    },
    get wallet() {
      return walletClient;
    },
    get provider() {
      return activeProvider;
    },
    get walletName() {
      return walletName;
    },
    get connecting() {
      return connecting;
    },
    get error() {
      return error;
    },
    get hasProvider() {
      return browser && pickProvider() !== null;
    },
    connect,
    restore,
    ensureChain
  };
}

export const wallet = createWallet();

if (browser && getIntent() === 'connected') {
  // EIP-6963 announcements may arrive after this module loads, so try
  // immediately and again whenever the provider list changes (bounded).
  void wallet.restore();
  if (mipdStore) {
    const unsub = mipdStore.subscribe(
      () => {
        if (wallet.account) return;
        void wallet.restore();
      },
      { emitImmediately: false }
    );
    setTimeout(() => unsub(), 5000);
  }
}

export function shortAddr(a: Address | string | null | undefined): string {
  return a ? `${a.slice(0, 6)}…${a.slice(-4)}` : '—';
}
