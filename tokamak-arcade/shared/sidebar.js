// Tokamak Arcade left rail — DEX-style sidebar with Play/Earn/Pools/Stats/...
// Mount with: mountTokamakSidebar(el, { active: 'play' | 'pools' | ... }).
// Adds the `tk-has-sidebar` class to <body>; layout offset comes from tokamak.css.
//
// All hrefs assume the consumer page lives one level under tokamak-arcade/
// (e.g. games/, pools/, flip/). Brand link goes to ../index.html.

import { TOKAMAK_SYMBOL_DATA_URI } from './brand.js';
import { t } from './lang.js';

const ICON = {
  play: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true">
    <path d="M8 5l11 7-11 7V5z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>
  </svg>`,
  earn: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true">
    <ellipse cx="12" cy="6.5" rx="7" ry="2.5" stroke="currentColor" stroke-width="1.6"/>
    <path d="M5 6.5v5c0 1.4 3.1 2.5 7 2.5s7-1.1 7-2.5v-5" stroke="currentColor" stroke-width="1.6"/>
    <path d="M5 11.5v5c0 1.4 3.1 2.5 7 2.5s7-1.1 7-2.5v-5" stroke="currentColor" stroke-width="1.6"/>
  </svg>`,
  pools: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true">
    <ellipse cx="12" cy="5.5" rx="8" ry="2.5" stroke="currentColor" stroke-width="1.6"/>
    <path d="M4 5.5v13c0 1.4 3.6 2.5 8 2.5s8-1.1 8-2.5v-13" stroke="currentColor" stroke-width="1.6"/>
    <path d="M4 12c0 1.4 3.6 2.5 8 2.5s8-1.1 8-2.5" stroke="currentColor" stroke-width="1.6"/>
  </svg>`,
  stats: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true">
    <path d="M4 19h16" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
    <rect x="6"  y="11" width="3" height="6"  rx="0.5" stroke="currentColor" stroke-width="1.6"/>
    <rect x="11" y="7"  width="3" height="10" rx="0.5" stroke="currentColor" stroke-width="1.6"/>
    <rect x="16" y="13" width="3" height="4"  rx="0.5" stroke="currentColor" stroke-width="1.6"/>
  </svg>`,
  leaderboard: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true">
    <path d="M5 21h14M9 21V11h6v10M12 11V5l-3 3M12 5l3 3" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>`,
  ecosystem: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true">
    <rect x="4"  y="4"  width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.6"/>
    <rect x="13" y="4"  width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.6"/>
    <rect x="4"  y="13" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.6"/>
    <rect x="13" y="13" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.6"/>
  </svg>`,
};

const NAV = [
  { key: 'play',        i18n: 'nav.play',        href: '../games/index.html', soon: false },
  { key: 'earn',        i18n: 'nav.earn',        href: '#',                   soon: true  },
  { key: 'pools',       i18n: 'nav.pools',       href: '#',                   soon: true  },
  { key: 'stats',       i18n: 'nav.stats',       href: '#',                   soon: true  },
  { key: 'leaderboard', i18n: 'nav.leaderboard', href: '#',                   soon: true  },
  { key: 'ecosystem',   i18n: 'nav.ecosystem',   href: '#',                   soon: true  },
];

export function mountTokamakSidebar(root, { active = '' } = {}) {
  const links = NAV.map(item => {
    const isActive = item.key === active;
    const isSoon = item.soon && !isActive;
    return `
      <a class="tk-sb-link${isActive ? ' active' : ''}"
         href="${isActive ? '' : item.href}"
         ${isActive ? 'aria-current="page"' : ''}
         ${isSoon ? 'aria-disabled="true"' : ''}>
        ${ICON[item.key]}
        <span data-i18n="${item.i18n}">${t(item.i18n)}</span>
        ${isSoon ? '<span class="tk-sb-soon">soon</span>' : ''}
      </a>`;
  }).join('');

  root.classList.add('tk-sb');
  root.innerHTML = `
    <a class="tk-sb-brand" href="../index.html">
      <img class="tk-sb-mark" src="${TOKAMAK_SYMBOL_DATA_URI}" alt="Tokamak Network">
      <span class="tk-sb-name">Tokamak <b>Arcade</b></span>
    </a>
    <nav class="tk-sb-nav">${links}</nav>
    <div class="tk-sb-foot">
      <span class="tk-sb-foot-dot"></span>
      <span data-i18n="nav.footer.testnet">${t('nav.footer.testnet')}</span>
    </div>`;

  document.body.classList.add('tk-has-sidebar');

  root.querySelectorAll('.tk-sb-link[aria-disabled="true"]').forEach(a => {
    a.addEventListener('click', e => e.preventDefault());
  });
}
