// Shared wallet helpers — viem-based, EIP-1193 (MetaMask or compatible).
import {
  createPublicClient, createWalletClient, custom, http,
  getAddress, defineChain,
} from 'https://esm.sh/viem@2.21.0';
import { CONFIG } from './config.js';

export const anvil = defineChain({
  id: CONFIG.chainId,
  name: 'Enshrined VRF Devnet',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: [CONFIG.rpc] } },
});

export const pub = createPublicClient({ chain: anvil, transport: http(CONFIG.rpc) });

let _wallet = null;
let _account = null;

export function hasProvider() { return typeof window !== 'undefined' && !!window.ethereum; }

const CHAIN_HEX = '0x' + CONFIG.chainId.toString(16);

async function currentChainId() {
  return await window.ethereum.request({ method: 'eth_chainId' });
}

async function ensureOnDevnet() {
  if ((await currentChainId()).toLowerCase() === CHAIN_HEX) return;

  // wallet_addEthereumChain bundles add + auto-switch in one popup, and is
  // a no-op when the chain is already registered. Calling switch first on an
  // unknown chain produces the "Unrecognized chain ID" error, so always add
  // first.
  try {
    await window.ethereum.request({
      method: 'wallet_addEthereumChain',
      params: [{
        chainId: CHAIN_HEX,
        chainName: anvil.name,
        rpcUrls: [CONFIG.rpc],
        nativeCurrency: anvil.nativeCurrency,
      }],
    });
  } catch (err) {
    if (err?.code === 4001) throw err; // user rejected
    // Some wallets refuse add for an already-registered chain — fall back to switch.
    await window.ethereum.request({
      method: 'wallet_switchEthereumChain',
      params: [{ chainId: CHAIN_HEX }],
    });
  }

  // Some wallets add without auto-switching. Confirm and switch if needed.
  if ((await currentChainId()).toLowerCase() !== CHAIN_HEX) {
    await window.ethereum.request({
      method: 'wallet_switchEthereumChain',
      params: [{ chainId: CHAIN_HEX }],
    });
  }
  if ((await currentChainId()).toLowerCase() !== CHAIN_HEX) {
    throw new Error(
      `MetaMask가 devnet(chainId ${CONFIG.chainId})으로 전환되지 않았습니다. ` +
      `네트워크 목록에서 "${anvil.name}"을 직접 선택해 주세요.`
    );
  }
}

export async function connect() {
  if (!hasProvider()) throw new Error('Install MetaMask to play.');
  await ensureOnDevnet();
  _wallet = createWalletClient({ chain: anvil, transport: custom(window.ethereum) });
  const accounts = await _wallet.requestAddresses();
  _account = getAddress(accounts[0]);
  // React to the user switching networks or accounts after connecting.
  window.ethereum.on?.('chainChanged',    () => window.location.reload());
  window.ethereum.on?.('accountsChanged', () => window.location.reload());
  return { account: _account };
}

export function account() { return _account; }
export function wallet()  { return _wallet; }

export function shortAddr(a) {
  return a ? `${a.slice(0, 6)}…${a.slice(-4)}` : '—';
}
