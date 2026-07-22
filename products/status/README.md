# Homelab public status

Failure-independent public status for the explicitly published family service
components in `generated/components.json`. The component file is generated from
the Nix inventory; edit workload manifests, not the JSON.

```bash
# From the repository root, after changing route publication metadata:
status_json=$(nix build .#status-json --no-link --print-out-paths)
cp "$status_json" products/status/generated/components.json

# From this directory:
bun install --frozen-lockfile
bun run check
bun alchemy plan --stage prod
bun alchemy deploy --stage prod
```

The plan and deploy commands contact Cloudflare and require a scoped deployment
credential. They are operator-gated and are never run by `nix flake check`.
The first Alchemy plan may bootstrap its Cloudflare state store, so even that
plan requires explicit mutation approval. D1 uses a retain removal policy;
destroying the stack removes the surface but preserves its history database.
Non-production stages receive stage-derived Worker and D1 names plus a
`workers.dev` URL; only the `prod` stage can claim `status.home.phibkro.org` or
install the scheduled probe trigger.

Alchemy owns one Worker custom domain, one D1 database, its migrations, and one
two-minute cron trigger. The initial Worker exposes only `GET /`, `HEAD /`, and
`GET /api/status`; it has no mutation credential or homelab control path.
