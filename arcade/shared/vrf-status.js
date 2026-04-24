// Top-bar VRF status — polls the EnshrainedVRF predeploy for commit activity.
import { parseAbi } from 'https://esm.sh/viem@2.21.0';
import { pub } from './wallet.js';
import { CONFIG } from './config.js';

const VRF_ABI = parseAbi([
  'function commitNonce() view returns (uint256)',
  'function callCounter() view returns (uint256)',
]);

export function mountVrfStatus(el) {
  el.innerHTML = `
    <div class="status" id="vrf-status">
      <span class="dot"></span>
      <span class="label">connecting…</span>
    </div>`;
  const status = el.querySelector('#vrf-status');
  const label  = status.querySelector('.label');

  let lastNonce = -1n;
  let lastSeen  = Date.now();

  async function tick() {
    try {
      const [nonce, block] = await Promise.all([
        pub.readContract({ address: CONFIG.vrfAddress, abi: VRF_ABI, functionName: 'commitNonce' }),
        pub.getBlockNumber(),
      ]);
      if (nonce !== lastNonce) {
        lastNonce = nonce;
        lastSeen = Date.now();
        status.className = 'status ok';
      } else if (Date.now() - lastSeen > 4000) {
        status.className = 'status stale';
      }
      label.textContent = `VRF #${nonce} · block ${block}`;
    } catch {
      status.className = 'status err';
      label.textContent = 'RPC unavailable';
    }
  }

  tick();
  return setInterval(tick, 900);
}
