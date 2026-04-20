#!/usr/bin/env node
// Convert `forge doc` output into Mintlify MDX files under docs-site/contracts/.
// Run: npm run sync-contracts (from docs-site/)

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DOCS_ROOT = resolve(__dirname, '..');
const CONTRACTS_ROOT = resolve(DOCS_ROOT, '..', 'contracts');
const FORGE_OUT = resolve(DOCS_ROOT, '.forge-doc');
const MDX_OUT = resolve(DOCS_ROOT, 'contracts');

// Map forge-doc source paths → (output slug, predeploy address, short description override)
const TARGETS = [
  {
    src: 'src/aa/GameRegistry.sol/contract.GameRegistry.md',
    slug: 'game-registry',
    address: '0x4200000000000000000000000000000000000000A2',
    title: 'GameRegistry',
    description: 'Whitelist of contracts session keys may call.',
  },
  {
    src: 'src/aa/SessionKeyManager.sol/contract.SessionKeyManager.md',
    slug: 'session-key-manager',
    address: '0x4200000000000000000000000000000000000000A1',
    title: 'SessionKeyManager',
    description: 'Registry and validator for scoped session keys.',
  },
  {
    src: 'src/aa/GameHubFactory.sol/contract.GameHubFactory.md',
    slug: 'game-hub-factory',
    address: '0x4200000000000000000000000000000000000000A0',
    title: 'GameHubFactory',
    description: 'Deterministic CREATE2 deployer for per-user GameHub accounts, plus single-signature onboarding and refill flows.',
  },
  {
    src: 'src/aa/GameHubAccount.sol/contract.GameHubAccount.md',
    slug: 'game-hub-account',
    address: null,
    title: 'GameHubAccount',
    description: 'Per-user smart account: owner for setup and withdrawal, session keys for gameplay.',
  },
  {
    src: 'src/L1/VRFVerifier.sol/contract.VRFVerifier.md',
    slug: 'vrf-verifier',
    address: null,
    title: 'VRFVerifier (L1)',
    description: 'Pure-Solidity ECVRF verifier used on L1 during fault-proof disputes.',
  },
];

// ─── helpers ──────────────────────────────────────────────────────────────

function runForgeDoc() {
  console.log('⟶  forge doc …');
  execSync(`forge doc --out ${FORGE_OUT}`, {
    cwd: CONTRACTS_ROOT,
    stdio: 'inherit',
  });
}

function transform(raw, target) {
  // Strip the first H1 — we replace with frontmatter.
  let body = raw.replace(/^# [^\n]+\n/, '');
  // Drop the "Git Source" line.
  body = body.replace(/^\[Git Source\][^\n]*\n+/m, '');
  // Drop the redundant "**Title:**\n<name>" block.
  body = body.replace(/^\*\*Title:\*\*\n[^\n]+\n+/m, '');
  // Trim excess whitespace at the top.
  body = body.replace(/^\s+/, '');

  const predeployBlock = target.address
    ? `<Info>\n  **Predeploy address:** \`${target.address}\`\n</Info>\n\n`
    : '';

  const frontmatter = [
    '---',
    `title: "${target.title}"`,
    `description: "${target.description}"`,
    '---',
    '',
    '<Note>',
    '  Auto-generated from Solidity NatSpec via `forge doc`. Hand edits here will be overwritten.',
    '  Run `npm run sync-contracts` from `docs-site/` to regenerate.',
    '</Note>',
    '',
    predeployBlock,
  ].join('\n');

  return frontmatter + body;
}

// ─── main ────────────────────────────────────────────────────────────────

function main() {
  runForgeDoc();

  if (!existsSync(MDX_OUT)) mkdirSync(MDX_OUT, { recursive: true });

  let written = 0;
  for (const target of TARGETS) {
    const inputPath = join(FORGE_OUT, 'src', target.src);
    if (!existsSync(inputPath)) {
      console.warn(`!  missing: ${inputPath}`);
      continue;
    }
    const raw = readFileSync(inputPath, 'utf8');
    const mdx = transform(raw, target);
    const outPath = join(MDX_OUT, `${target.slug}.mdx`);
    writeFileSync(outPath, mdx);
    console.log(`✓  ${target.slug}.mdx`);
    written++;
  }
  console.log(`\n${written}/${TARGETS.length} contract pages regenerated.`);
}

main();
