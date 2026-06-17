---
name: gotcha-tailscale-serve-set-config-schema
description: USE WHEN trying to configure `tailscale serve` declaratively via `set-config` JSON — schema is a moving target across tailscaled versions, `get-config --all` returns empty so reverse-engineering doesn't work. Use the imperative `tailscale serve --bg --https <port> --set-path <path> <target>` approach from `modules/infra/funnel-route.nix`. <!-- path-coherence: skip — funnel feature removed in d0cee68; skill retained for future re-introduction -->
---

# `tailscale serve set-config` schema is a moving target

As of 1.96.5, the JSON schema for `tailscale serve set-config` requires both:

- `--all` or `--service=svc:<n>` flag (otherwise: `must specify either ...`)
- `"version": "0.0.1"` field (otherwise: `config file must have "version" field`)

But even with both, the format groups under `services.<n>` and rejects top-level `TCP`/`Web`/`AllowFunnel`. `tailscale serve get-config --all` returns just `{"version": "0.0.1"}` — empty — so reverse-engineering the right shape isn't viable.

Workaround in `modules/infra/funnel-route.nix`: imperative `tailscale serve --bg --https <port> --set-path ... <target>` commands, one per route, with `tailscale serve reset` at the start of each activation to drop removed routes. tailscaled-side state persists; declarative end-state semantics from imperative primitives. <!-- path-coherence: skip — file removed in d0cee68 -->
