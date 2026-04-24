// Polls the EnshrinedVRF predeploy — same cadence as arcade/shared/vrf-status.js
// but rendered as a cream pastel pill with hand-drawn outline.
// UI only shows the block number; commitNonce drives the staleness colour behind
// the scenes (so we still catch a stuck sequencer even though the number is hidden).
import { parseAbi } from 'https://esm.sh/viem@2.21.0';
import { pub } from './wallet.js';
import { CONFIG } from './config.js';
import { t } from './lang.js';

const VRF_ABI = parseAbi([
  'function commitNonce() view returns (uint256)',
  'function callCounter() view returns (uint256)',
]);

export function mountVrfStatus(el) {
  el.innerHTML = `
    <div class="vrf-pill" id="tokamak-vrf">
      <span class="dot"></span>
      <span class="label"></span>
    </div>`;
  const pill  = el.querySelector('#tokamak-vrf');
  const label = pill.querySelector('.label');
  label.textContent = t('common.vrf.waking');

  let lastNonce = -1n;
  let lastSeen  = Date.now();
  let lastStatus = 'waking';

  async function tick() {
    try {
      const [nonce, block] = await Promise.all([
        pub.readContract({ address: CONFIG.vrfAddress, abi: VRF_ABI, functionName: 'commitNonce' }),
        pub.getBlockNumber(),
      ]);
      if (nonce !== lastNonce) {
        lastNonce = nonce; lastSeen = Date.now();
        pill.className = 'vrf-pill ok';
      } else if (Date.now() - lastSeen > 4000) {
        pill.className = 'vrf-pill stale';
      }
      label.textContent = `blk ${block}`;
      lastStatus = 'live';
    } catch {
      pill.className = 'vrf-pill err';
      label.textContent = t('common.vrf.offline');
      lastStatus = 'offline';
    }
  }

  // Re-translate the two static labels ("waking up…", "RPC offline") on lang change.
  document.addEventListener('tokamak:langchange', () => {
    if (lastStatus === 'offline') label.textContent = t('common.vrf.offline');
    else if (lastNonce === -1n)   label.textContent = t('common.vrf.waking');
  });

  tick();
  return setInterval(tick, 900);
}
