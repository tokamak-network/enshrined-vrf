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

The `vercel.json` at this directory's root is already wired for Vercel:

- `buildCommand`: `npm run build`
- `outputDirectory`: `out`
- `installCommand`: `npm install`

### One-time setup

1. In Vercel dashboard, import the repo.
2. Set **Root Directory** to `docs-site`.
3. Leave framework preset as "Other". Vercel will pick up `vercel.json`.
4. Add any custom domain under Project → Domains.

Subsequent pushes to `main` trigger automatic preview + production deploys.

### Manual deploy via CLI

```bash
npm install -g vercel
vercel --cwd docs-site          # preview
vercel --cwd docs-site --prod   # production
```

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
