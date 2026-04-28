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

function hasProvider(): boolean {
  return browser && !!window.ethereum;
}

function createWallet() {
  let account = $state<Address | null>(null);
  let walletClient = $state<WalletClient | null>(null);
  let connecting = $state(false);
  let error = $state<string | null>(null);

  async function currentChainId(): Promise<string> {
    return (await window.ethereum!.request({ method: 'eth_chainId' })) as string;
  }

  async function ensureOnDevnet() {
    if ((await currentChainId()).toLowerCase() === CHAIN_HEX) return;

    try {
      await window.ethereum!.request({
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
      await window.ethereum!.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: CHAIN_HEX }]
      });
    }

    if ((await currentChainId()).toLowerCase() !== CHAIN_HEX) {
      await window.ethereum!.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: CHAIN_HEX }]
      });
    }
    if ((await currentChainId()).toLowerCase() !== CHAIN_HEX) {
      throw new Error(
        `MetaMask did not switch to devnet (chainId ${CONFIG.chainId}). ` +
          `Please pick "${anvil.name}" from the network list manually.`
      );
    }
  }

  async function connect() {
    if (!hasProvider()) throw new Error('Install MetaMask to play.');
    connecting = true;
    error = null;
    try {
      await ensureOnDevnet();
      const wc = createWalletClient({
        chain: anvil,
        transport: custom(window.ethereum!)
      });
      const accounts = await wc.requestAddresses();
      walletClient = wc;
      account = getAddress(accounts[0]);

      window.ethereum!.on?.('chainChanged', () => window.location.reload());
      window.ethereum!.on?.('accountsChanged', () => window.location.reload());
      return account;
    } catch (err) {
      const e = err as { message?: string };
      error = e?.message ?? String(err);
      throw err;
    } finally {
      connecting = false;
    }
  }

  return {
    get account() {
      return account;
    },
    get wallet() {
      return walletClient;
    },
    get connecting() {
      return connecting;
    },
    get error() {
      return error;
    },
    get hasProvider() {
      return hasProvider();
    },
    connect
  };
}

export const wallet = createWallet();

export function shortAddr(a: Address | string | null | undefined): string {
  return a ? `${a.slice(0, 6)}…${a.slice(-4)}` : '—';
}
