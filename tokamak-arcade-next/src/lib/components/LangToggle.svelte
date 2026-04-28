<script lang="ts">
  import { i18n } from '$lib/i18n.svelte';
</script>

<button
  type="button"
  class="lang-toggle"
  aria-label="Toggle language"
  onclick={() => i18n.toggle()}
>
  <span class="lang-opt" class:active={i18n.lang === 'ko'}>KO</span>
  <span class="lang-opt" class:active={i18n.lang === 'en'}>EN</span>
</button>
