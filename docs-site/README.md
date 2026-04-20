# Enshrined VRF Docs

Public-facing documentation site, built with [Mintlify](https://mintlify.com/).

## Local development

```bash
cd docs-site
npx mintlify dev
```

Opens at `http://localhost:3000`.

## Build (for any static host)

```bash
npm run build
```

Produces a fully static Next.js export under `out/`. The build runs
`sync-contracts` first, then `mintlify export`, and unzips the archive
into `out/`.

## Deploying to Vercel

Use the **prebuilt** path only. Vercel's automatic static-build step
re-runs `mintlify export` without the `--disable-openapi` flag, which
bloats every page to ~53 MB and breaks client-side hydration. Running
the build locally first and uploading with `--prebuilt` sidesteps that.

### First time

```bash
vercel link        # link to an existing Vercel project (or create one)
```

Leave **Root Directory** as `docs-site`, framework as "Other".

### Deploy

```bash
npm run deploy:preview   # preview URL
npm run deploy:prod      # promote to production
```

These scripts run `npm run build` locally, assemble the Vercel
Build Output v3 layout under `.vercel/output/`, then upload with
`vercel deploy --prebuilt`. No rebuild on Vercel's side.

## Structure

- `docs.json` — navigation, theme, navbar, footer
- `introduction.mdx`, `quickstart.mdx` — top-level onboarding
- `concepts/` — mental model (VRF, session accounts, predeploys)
- `guides/` — how-tos for game devs and frontend integrators
- `contracts/` — per-contract reference (auto-generated from NatSpec in a later pass)

## Adding a page

1. Create a new `.mdx` file in the appropriate folder.
2. Add the path (without the `.mdx` suffix) to the right group in `docs.json`.
3. Preview with `mintlify dev`.

## Relationship to `docs/`

`docs/` at the repo root holds **internal** design documents (PRDs, phase reports, issue drafts). `docs-site/` is the **external** developer-facing product. Content overlaps on purpose — different tones, different audiences.
