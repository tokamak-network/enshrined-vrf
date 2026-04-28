<script lang="ts">
  import { i18n } from '$lib/i18n.svelte';
  import { wallet, shortAddr } from '$lib/wallet.svelte';
  import { TOKAMAK_SYMBOL_DATA_URI } from '$lib/brand';
  import LangToggle from './LangToggle.svelte';
  import VrfStatus from './VrfStatus.svelte';

  type Props = { hubHref?: string; brand?: boolean };
  let { hubHref = '/', brand = true }: Props = $props();

  const label = $derived.by(() => {
    if (wallet.connecting) return i18n.t('common.connecting');
    if (wallet.account) return shortAddr(wallet.account);
    if (!wallet.hasProvider) return i18n.t('common.noWallet');
    return i18n.t('common.connect');
  });

  async function onConnect() {
    if (wallet.account) return;
    try {
      await wallet.connect();
    } catch (err) {
      const e = err as { message?: string };
      console.error('[connect]', err);
      alert(e?.message ?? String(err));
    }
  }
</script>

<div class="tokamak-topbar">
  {#if brand}
    <a class="tokamak-brand" href={hubHref}>
      <span class="logo">
        <img src={TOKAMAK_SYMBOL_DATA_URI} alt="Tokamak Network" class="logo-img" />
      </span>
      <span class="title">Tokamak <b>Arcade</b></span>
    </a>
  {:else}
    <span class="tokamak-topbar-spacer" aria-hidden="true"></span>
  {/if}

  <div class="tokamak-topbar-right">
    <VrfStatus />
    <LangToggle />
    <button
      type="button"
      class="tokamak-btn small"
      disabled={wallet.connecting}
      onclick={onConnect}
    >
      {label}
    </button>
  </div>
</div>
