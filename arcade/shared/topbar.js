// Shared top bar — brand + wallet pill + VRF status.
import { connect, account, shortAddr, hasProvider } from './wallet.js';
import { mountVrfStatus } from './vrf-status.js';

export function mountTopbar(root) {
  root.innerHTML = `
    <div class="topbar">
      <a class="brand" href="../index.html">
        <span class="logo">V</span>
        <span>Enshrined <b>VRF Arcade</b></span>
      </a>
      <div class="row" style="gap:14px">
        <div id="vrf-status-slot"></div>
        <button class="btn ghost" id="connect-btn">connect</button>
      </div>
    </div>`;

  const btn = root.querySelector('#connect-btn');
  const refreshBtn = () => {
    const a = account();
    btn.textContent = a ? shortAddr(a) : (hasProvider() ? 'connect' : 'no wallet');
  };
  btn.addEventListener('click', async () => {
    if (account()) return;
    btn.disabled = true; btn.textContent = 'connecting…';
    try {
      await connect();
      refreshBtn();
    } catch (err) {
      console.error('[connect]', err);
      alert(err?.message || String(err));
      btn.textContent = 'retry';
      setTimeout(() => { btn.disabled = false; refreshBtn(); }, 800);
      return;
    }
    btn.disabled = false;
  });
  refreshBtn();

  mountVrfStatus(root.querySelector('#vrf-status-slot'));
}

export function requireWallet(fn) {
  return async (...args) => {
    if (!account()) {
      try { await connect(); }
      catch (err) { alert(err.message || 'connect failed'); throw err; }
    }
    return fn(...args);
  };
}
