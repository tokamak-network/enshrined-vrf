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

  // Try to switch first — succeeds if the user has already added the network
  // (possibly under a different name, e.g. "Tokamak Sandbox").
  try {
    await window.ethereum.request({
      method: 'wallet_switchEthereumChain',
      params: [{ chainId: CHAIN_HEX }],
    });
  } catch (err) {
    // 4902 = unrecognized chain; add it. Some wallets bundle add+switch; others don't.
    if (err?.code !== 4902 && !/Unrecognized chain/i.test(err?.message || '')) throw err;
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
    } catch (addErr) {
      // MetaMask refuses to add a duplicate network when an existing entry
      // (e.g. "Tokamak Sandbox") already points to the same chainId + RPC.
      // That's fine — the network is already there; just switch to it.
      if (!/same RPC endpoint|existing network/i.test(addErr?.message || '')) throw addErr;
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: CHAIN_HEX }],
      });
    }
  }

  // Verify (and retry switch if add didn't auto-activate).
  if ((await currentChainId()).toLowerCase() !== CHAIN_HEX) {
    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: CHAIN_HEX }],
      });
    } catch { /* user rejected — surface a clear error below */ }
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
