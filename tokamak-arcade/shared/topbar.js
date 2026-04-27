// Tokamak-styled top bar: brand + VRF pill + KO/EN toggle + connect pill.
import { connect, account, shortAddr, hasProvider } from './wallet.js';
import { mountVrfStatus } from './vrf-status.js';
import { t, mountLangToggle } from './lang.js';
import { TOKAMAK_SYMBOL_DATA_URI } from './brand.js';

export function mountTokamakTopbar(root, { hubHref = '../index.html', brand = true } = {}) {
  // When the sidebar is mounted it owns the brand mark, so callers pass
  // brand:false to keep the topbar a status-only strip (VRF + lang + connect).
  const brandHTML = brand
    ? `<a class="tokamak-brand" href="${hubHref}">
         <span class="logo"><img src="${TOKAMAK_SYMBOL_DATA_URI}" alt="Tokamak Network" class="logo-img"></span>
         <span class="title">Tokamak <b>Arcade</b></span>
       </a>`
    : `<span class="tokamak-topbar-spacer" aria-hidden="true"></span>`;

  root.innerHTML = `
    <div class="tokamak-topbar">
      ${brandHTML}
      <div class="tokamak-topbar-right">
        <div id="tokamak-vrf-slot"></div>
        <div id="tokamak-lang-slot"></div>
        <button class="tokamak-btn small" id="tokamak-connect"></button>
      </div>
    </div>`;

  const btn = root.querySelector('#tokamak-connect');
  const paint = () => {
    const a = account();
    btn.textContent = a ? shortAddr(a)
                        : (hasProvider() ? t('common.connect') : t('common.noWallet'));
  };
  btn.addEventListener('click', async () => {
    if (account()) return;
    btn.disabled = true; btn.textContent = t('common.connecting');
    try { await connect(); paint(); }
    catch (err) {
      console.error('[connect]', err);
      alert(err?.message || String(err));
      btn.textContent = t('common.retry');
      setTimeout(() => { btn.disabled = false; paint(); }, 800);
      return;
    }
    btn.disabled = false;
  });
  paint();

  mountVrfStatus(root.querySelector('#tokamak-vrf-slot'));
  mountLangToggle(root.querySelector('#tokamak-lang-slot'));

  // Re-render label strings on language change (connect pill lives outside [data-i18n]).
  document.addEventListener('tokamak:langchange', paint);
}
