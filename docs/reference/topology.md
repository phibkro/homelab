---
summary: Cross-module topology synthesis — service placement decisions, the split-module pattern for cross-host services, resource caps, operator facts. The single-module narrative (host roles, topology graph, the tier principle, per-host hardware posture) lives in `docs/generated/topology.md`, extracted from `modules/machines/default.nix` and each host's `hardware.nix`. GPU access pattern moved to `docs/generated/capabilities.md`.
---

# Topology — cross-module synthesis

The single-module narrative (topology graph, the
service-implicit-until-lan-route'd tier principle, the `nori.hosts`
schema + hosts-at-a-glance table, per-host hardware posture) lives in
[`docs/generated/topology.md`](../generated/topology.md), extracted
from `modules/machines/default.nix` + each host's `hardware.nix`. The
GPU access pattern moved to
[`docs/generated/capabilities.md`](../generated/capabilities.md)
alongside the `nori.gpu` schema. This file keeps the cross-module
content that doesn't fit one extraction site.

## Service placement

| Cluster | Where | Why |
|---|---|---|
| HTTP entry plane (Caddy + Authelia) | pi | ADR-0003 — entry plane on the always-on appliance so workstation can sleep. Pi's Caddy serves the LE wildcard cert on `*.${nori.domain}` (ADR-0004); Authelia provides OIDC; backends proxy to whatever host actually runs the service via the lan-route module's `runsOn` resolver |
| GPU-bound (Ollama, Jellyfin NVENC, `*arr` stack, qBittorrent, Open WebUI) | workstation | RTX 5060 Ti — primary GPU |
| ML inference (Immich machine-learning / PyTorch) | aurora | Co-located with immich-server; GTX 950M is sufficient. `IMMICH_MACHINE_LEARNING_URL` resolves to aurora's tailnet IP |
| Family-tier services (Vaultwarden, Radicale, Miniflux, Immich, Calibre-web, Komga, Glance, Heim, Filmder, Grafana) | aurora | Always-on so they survive workstation sleep / outage; ADR-0002 |
| Family-tier file storage (`/mnt/family/{photos,home-videos,projects,library,archive}`) | aurora | Family vault — Toshiba HDD, btrfs label `family-vault` |
| Family Samba shares | aurora | Follows the drive — per-fs `samba = { }` blocks in `modules/machines/aurora/disko-family.nix` |
| Workstation Samba shares (`media`, `share`, `nori`) | workstation | Whole-drive `media` share scoped to `/mnt/media` (IronWolf root) stays workstation-only; per-fs `share` + `nori` shares stay workstation-only via the gated workstation-shape check in `samba.nix` |
| Observability + alert plane (Beszel hub, Gatus, VictoriaMetrics, VictoriaLogs, ntfy server) | pi | Must survive workstation outage — that's *when* they fire |
| Heartbeat / dead-man-switch (healthchecks.io ping) | pi | SPOF mitigation — see `modules/infra/observability/heartbeat.nix` |
| DNS authoritative for `*.${nori.domain}` (Blocky self-hosted) | pi | ADR-0003 prerequisite for the LE wildcard issuance (ADR-0004). Workstation's Blocky stays as a secondary self-hosted forwarder for LAN-side resilience if pi is down |
| Network plumbing (subnet router + exit node) | pi | Appliance role; opt-in per device for exit node |
| Agent quarantine (hermes-agent CLI + dashboard) | pavilion | Sandboxed; pavilion's impermanence root makes pollution self-healing |
| Process metrics (`node-exporter` + `process-exporter`) | workstation + pavilion + aurora | Pi VM scrapes each; per-process RSS for leak hunts |
| Host-level high-level metrics (`beszel-agent`) | workstation + pavilion + aurora | Pi's Beszel hub aggregates per-host |
| OnFailure → ntfy notifier (`ntfy-notify`) | workstation + pi + aurora | Per-host so the alert source is unambiguous and aurora-side unit failures (restic, btrbk, postgres dumps) page the operator without depending on workstation being awake |

Placement test = **fate-sharing breaks the function** (not "feels
lightweight"). See `docs/glossary.md § fate-sharing`. This table is a
cross-effect view — placement reasoning crosses module, lan-route, and
observability surfaces; no single code home.

## Cross-host services (split-module pattern)

Daemon on one host, client/proxy on every consumer. Cross-host Caddy
lanRoute gated `lib.mkIf config.services.caddy.enable` so daemon-host's
Blocky stays pure-forwarder.

| Service | Daemon | Routed at | Client module |
|---|---|---|---|
| Beszel | pi | `metrics.${nori.domain}` | `modules/infra/observability/beszel/agent.nix` everywhere |
| ntfy | pi | `alert.${nori.domain}` | `modules/infra/observability/ntfy/notify.nix` everywhere |
| VictoriaLogs | pi | `logs.${nori.domain}` | `modules/infra/observability/vector.nix` ships journald |
| VictoriaMetrics | pi | `tsdb.${nori.domain}` (Grafana datasource) | `modules/infra/observability/node-exporter.nix` scraped from pi |
| immich-ml | aurora | n/a (RPC only) | `modules/services/immich.nix` (workstation) — `IMMICH_MACHINE_LEARNING_URL` |
| hermes-agent | pavilion (planned) → currently workstation | `hermes.${nori.domain}` | `modules/home/hermes/default.nix` (PCs) |

Add another via `/relocate-to-pi` skill. Precedents above.

## Resource caps (where it matters)

| Service / system | Cap | Reason |
|---|---|---|
| `immich-machine-learning.serviceConfig` (aurora) | (moved to aurora; cap deprecated on workstation) | Original cap guarded the userspace-CPU-starvation pattern that wedged workstation 2026-04-28 (rtkit canary starved 4+ minutes; commit `c0a557d`). Aurora-offload removed the host-wedge risk |
| `zramSwap` on workstation | 16 GiB compressed | Required for nvcc/CUDA builds; previously OOM'd + hard-hung the host |
| `swapDevices` on workstation | 8 GiB disk swapfile (`/swapfile` on `@` btrfs subvol, NoCoW) | Overflow tier behind zram — landed 2026-06-06 after the memory-pressure freeze. Priority -2 (zram is 5) |
| `swapDevices` on pi | `[ ]` (no swap) | Anti-write posture for flash storage |
| `MemoryHigh` per heavy service | (deferred — ROADMAP) | Waiting on 7+ days of `process-exporter` data before sizing caps |

## Operator facts

- Single user `nori`, passwordless wheel sudo, SSH key-only.
- CPU cooler repasted 2026-04-29 — sustained 12-thread load ~72°C (was 95°C TJ_max throttling pre-repaste).

## Adding a host

See `/add-host`. Short version:

1. Create `modules/machines/<name>/` (folder name = `networking.hostName` — injected, don't redeclare).
2. Add the new entry to BOTH `nixosMachines` AND `identityFor` in `modules/machines/default.nix`. The key-set assertion fails eval if either is missing.
3. **Add the new host's age public key** (derived from its SSH host key via `ssh-to-age`) to `.sops.yaml` and run `sops updatekeys secrets/secrets.yaml` to re-encrypt existing secrets so the new host can decrypt them. Without this, sops secrets are unreachable on first boot.
4. First boot → `tailscale up` → approve in admin console for subnet route / exit node if applicable.
