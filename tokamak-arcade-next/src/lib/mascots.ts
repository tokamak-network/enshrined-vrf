// Hand-drawn tokamak mascots — kept as inline SVG strings so any host can drop
// them into a container with @html. Identical to the legacy shared/mascots.js.

const STROKE = '#2B2139';

export type MascotOpts = { size?: number };
export type Mascot = (opts?: MascotOpts) => string;

export const moonMascot: Mascot = ({ size = 88 } = {}) => `
<svg viewBox="0 0 120 120" width="${size}" height="${size}" fill="none">
  <g stroke="${STROKE}" stroke-width="3.5" stroke-linejoin="round" stroke-linecap="round">
    <path d="M78 28 a34 34 0 1 0 0 64 a26 26 0 1 1 0 -64 z" fill="#FFE29A"/>
    <circle cx="64" cy="52" r="2.4" fill="${STROKE}"/>
    <circle cx="76" cy="64" r="2.4" fill="${STROKE}"/>
    <path d="M62 72 q5 4 10 0" />
    <path d="M26 34 l4 0 M28 32 l0 4" />
    <path d="M98 94 l4 0 M100 92 l0 4" />
    <path d="M22 84 l3 0 M23.5 82.5 l0 3" />
  </g>
</svg>`;

export const catMascot: Mascot = ({ size = 88 } = {}) => `
<svg viewBox="0 0 120 120" width="${size}" height="${size}" fill="none">
  <g stroke="${STROKE}" stroke-width="3.5" stroke-linejoin="round" stroke-linecap="round">
    <path d="M34 42 L28 22 L46 32 Z" fill="#FFB3D9"/>
    <path d="M86 42 L92 22 L74 32 Z" fill="#FFB3D9"/>
    <ellipse cx="60" cy="58" rx="32" ry="28" fill="#FFF1E0"/>
    <circle cx="48" cy="56" r="4" fill="${STROKE}"/>
    <circle cx="72" cy="56" r="4" fill="${STROKE}"/>
    <circle cx="49" cy="55" r="1.3" fill="#fff"/>
    <circle cx="73" cy="55" r="1.3" fill="#fff"/>
    <path d="M58 66 l2 2 l2 -2" />
    <path d="M60 68 q-4 4 -8 2 M60 68 q4 4 8 2" />
    <path d="M36 64 l-10 -2 M36 68 l-10 2" />
    <path d="M84 64 l10 -2 M84 68 l10 2" />
    <rect x="88" y="78" width="18" height="18" rx="4" fill="#FFE29A" transform="rotate(-12 97 87)"/>
    <circle cx="93" cy="83" r="1.6" fill="${STROKE}" transform="rotate(-12 97 87)"/>
    <circle cx="101" cy="91" r="1.6" fill="${STROKE}" transform="rotate(-12 97 87)"/>
  </g>
</svg>`;

export const cloudMascot: Mascot = ({ size = 88 } = {}) => `
<svg viewBox="0 0 120 120" width="${size}" height="${size}" fill="none">
  <g stroke="${STROKE}" stroke-width="3.5" stroke-linejoin="round" stroke-linecap="round">
    <path d="M30 58
             a16 16 0 0 1 18 -14
             a20 20 0 0 1 38 4
             a14 14 0 0 1 -4 28
             l-48 0
             a14 14 0 0 1 -4 -18 z" fill="#B5DFF5"/>
    <circle cx="50" cy="54" r="2" fill="${STROKE}"/>
    <circle cx="72" cy="54" r="2" fill="${STROKE}"/>
    <path d="M54 62 q6 5 12 0" />
    <circle cx="40" cy="88"  r="5" fill="#FFE29A"/>
    <circle cx="60" cy="96"  r="5" fill="#FFB3D9"/>
    <circle cx="82" cy="86"  r="5" fill="#B5EAD7"/>
  </g>
</svg>`;

export const unicornMascot: Mascot = ({ size = 88 } = {}) => `
<svg viewBox="0 0 120 120" width="${size}" height="${size}" fill="none">
  <g stroke="${STROKE}" stroke-width="3.5" stroke-linejoin="round" stroke-linecap="round">
    <path d="M22 78
             c0 -18 18 -30 36 -30
             c20 0 34 12 34 28
             l-6 12
             l-14 0
             l-4 -6
             l-22 0
             l-4 6
             l-14 0
             l-6 -10 z" fill="#D7B5F5"/>
    <path d="M84 54 q8 -4 10 4 q-6 0 -10 4" fill="#FFB3D9"/>
    <path d="M80 62 q10 -2 10 8 q-8 -2 -12 0" fill="#FFE29A"/>
    <path d="M70 38 l6 -16 l4 16 z" fill="#FFE29A"/>
    <circle cx="78" cy="68" r="2.8" fill="${STROKE}"/>
    <path d="M88 76 q-4 4 -8 0" />
    <path d="M30 40 l2 0 M31 39 l0 2" />
    <path d="M100 30 l3 0 M101.5 28.5 l0 3" />
  </g>
</svg>`;

export const jankenMascot: Mascot = ({ size = 88 } = {}) => `
<svg viewBox="0 0 120 120" width="${size}" height="${size}" fill="none">
  <g stroke="${STROKE}" stroke-width="3.2" stroke-linejoin="round" stroke-linecap="round">
    <rect x="12" y="46" width="28" height="28" rx="8" fill="#FFB5A7" transform="rotate(-6 26 60)"/>
    <circle cx="26" cy="60" r="6" fill="none"/>
    <path d="M20 58 q6 3 12 0 M22 64 q4 2 8 0" transform="rotate(-6 26 60)"/>
    <rect x="46" y="34" width="28" height="36" rx="6" fill="#FFF1E0" transform="rotate(3 60 52)"/>
    <path d="M52 42 l16 0 M52 50 l16 0 M52 58 l10 0" transform="rotate(3 60 52)"/>
    <rect x="80" y="46" width="28" height="28" rx="8" fill="#B5DFF5" transform="rotate(8 94 60)"/>
    <g transform="rotate(8 94 60)">
      <circle cx="88" cy="56" r="4" fill="none"/>
      <circle cx="88" cy="66" r="4" fill="none"/>
      <path d="M90 56 L102 50 M90 66 L102 72" />
    </g>
    <path d="M60 92 l2 6 l6 -2 l-4 4 l4 4 l-6 -2 l-2 6 l-2 -6 l-6 2 l4 -4 l-4 -4 l6 2 z" fill="#FFE29A"/>
  </g>
</svg>`;

export const rainbowMascot: Mascot = ({ size = 88 } = {}) => `
<svg viewBox="0 0 120 120" width="${size}" height="${size}" fill="none">
  <g stroke="${STROKE}" stroke-width="3.5" stroke-linecap="round" fill="none">
    <path d="M18 90 a42 42 0 0 1 84 0" stroke="#FF7AB8"/>
    <path d="M26 90 a34 34 0 0 1 68 0" stroke="#FFC94D"/>
    <path d="M34 90 a26 26 0 0 1 52 0" stroke="#5FCFA4"/>
    <path d="M42 90 a18 18 0 0 1 36 0" stroke="#5FB8E6"/>
    <path d="M10 94 q8 -10 20 -6 q4 -8 14 -4 l0 10 z" fill="#FFF1E0" stroke-linejoin="round"/>
    <path d="M110 94 q-8 -10 -20 -6 q-4 -8 -14 -4 l0 10 z" fill="#FFF1E0" stroke-linejoin="round"/>
    <path d="M60 34 l0 8 M56 38 l8 0" stroke-width="3"/>
  </g>
</svg>`;

export const pongyMascot: Mascot = ({ size = 88 } = {}) => `
<svg viewBox="0 0 120 120" width="${size}" height="${size}" fill="none">
  <g stroke="${STROKE}" stroke-width="3.5" stroke-linejoin="round" stroke-linecap="round">
    <circle cx="40" cy="60" r="20" fill="#FFB5A7"/>
    <circle cx="80" cy="60" r="20" fill="#B5DFF5"/>
    <path d="M32 58 l16 0 M32 64 l16 0" />
    <path d="M72 58 l16 0 M72 64 l16 0" />
    <path d="M58 48 l4 4 l-4 4 l-4 -4 z" fill="#FFE29A"/>
    <path d="M58 72 l3 3 l-3 3 l-3 -3 z" fill="#FFE29A"/>
  </g>
</svg>`;
