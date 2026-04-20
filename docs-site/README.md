# Enshrined VRF Docs

Public-facing documentation site, built with [Mintlify](https://mintlify.com/).

## Local development

```bash
cd docs-site
npx mintlify dev
```

Opens at `http://localhost:3000`.

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
