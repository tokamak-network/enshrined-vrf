<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { parseAbi } from 'viem';
  import { pub } from '$lib/wallet.svelte';
  import { CONFIG } from '$lib/config';
  import { i18n } from '$lib/i18n.svelte';

  const VRF_ABI = parseAbi([
    'function commitNonce() view returns (uint256)',
    'function callCounter() view returns (uint256)'
  ]);

  let status = $state<'waking' | 'ok' | 'stale' | 'err'>('waking');
  let blockNum = $state<bigint | null>(null);

  let lastNonce = -1n;
  let lastSeen = Date.now();
  let timer: ReturnType<typeof setInterval> | null = null;

  const label = $derived.by(() => {
    if (status === 'err') return i18n.t('common.vrf.offline');
    if (blockNum === null) return i18n.t('common.vrf.waking');
    return `blk ${blockNum}`;
  });

  async function tick() {
    try {
      const [nonce, block] = await Promise.all([
        pub.readContract({
          address: CONFIG.vrfAddress,
          abi: VRF_ABI,
          functionName: 'commitNonce'
        }),
        pub.getBlockNumber()
      ]);
      if (nonce !== lastNonce) {
        lastNonce = nonce;
        lastSeen = Date.now();
        status = 'ok';
      } else if (Date.now() - lastSeen > 4000) {
        status = 'stale';
      }
      blockNum = block;
    } catch {
      status = 'err';
    }
  }

  onMount(() => {
    tick();
    timer = setInterval(tick, 900);
  });

  onDestroy(() => {
    if (timer) clearInterval(timer);
  });
</script>

<div class="vrf-pill {status}">
  <span class="dot"></span>
  <span class="label">{label}</span>
</div>
