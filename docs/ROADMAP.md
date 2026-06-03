---
summary: The forward plan — single home for outstanding work, deferred items, and
  idea backlog. Routine done-work lives in git log; durable design lives in DESIGN.md.
---

# Roadmap

The forward plan: actionable outstanding work, deferred-but-tracked items, and
the idea backlog. **This is the single home for "what's next"** — DESIGN.md
records the *why* (durable design), `git log` records what shipped. Items leave
this file when done (folded into git log / DESIGN.md) or when explicitly killed.

## Outstanding (actionable)

- ~~**Migration to next stable channel**~~ — **DONE 2026-06-03** (commit `4c8eab3`).
  Pinned to `nixos-26.05` + matched `home-manager`/`stylix` release-26.05 branches.
  One state-strand on the move: `redis-immich`'s RDB v14 (written by unstable
  Redis 9.x) couldn't be read by 26.05's Redis 8.6.3 — recovery was wiping the
  cache-class dump.rdb. Codified as a gotcha (`docs/gotchas.md` "Downgrading
  nixpkgs can strand persistent state"). All other state-heavy services
  (Postgres, Vaultwarden, ntfy, Immich's Postgres + filesystem) survived the
  downgrade unchanged. See DESIGN.md "Channel" section for the durable record.
- **Mac is on x86_64-darwin EOL clock** — Mac home-manager landed
  (`homeConfigurations.macbook` in `flake.nix`, content at
  `machines/macbook/home.nix`, pulls shared `nixpkgs` + `home-manager` unstable
  inputs). Switch via
  `nix run home-manager/master -- switch --flake ~/Documents/nix-migration#macbook`.
  Nix on the Mac was installed via **Determinate Nix installer v3.12.2**
  (released 2025-11-05) — the last Determinate release with an `x86_64-darwin`
  binary; v3.12.3 (2025-11-10) dropped Intel Mac support. Future Intel-Mac
  installs need to pin v3.12.2 specifically or use upstream installer. **Nixpkgs
  26.05 is announced as the LAST release supporting x86_64-darwin** (release-notes
  link surfaces in eval warnings). Decision needed ~May 2026 when 26.05 ships: pin
  Mac to 26.05 indefinitely, migrate Mac off Nix, or replace hardware. Practical
  adaptation already started: prefer ad-hoc `nix shell` over `home.packages` for
  heavy compiles (`yt-dlp` pulls `deno → rusty-v8`, Hydra cache is thin on
  x86_64-darwin) — keeps the home closure shippable. ghostty + utm stay on brew
  (no Darwin in nixpkgs `meta.platforms` for ghostty). Caddy local CA wired into
  Node clients via `home.sessionVariables.NODE_EXTRA_CA_CERTS` in
  `machines/macbook/home.nix` — handles immich-cli + claude-code MCP fetches that
  hit `*.nori.lan`.
- **Jellyfin NVENC web UI toggle** — `https://media.nori.lan` → Dashboard →
  Playback → Hardware acceleration → Nvidia NVENC + tick codec boxes
  (h264/hevc/mpeg4/vp9/av1) → Save. OS-level GPU access is already live; this
  flips `<HardwareAccelerationType>` from `none` to `nvenc` in
  `/var/lib/jellyfin/config/encoding.xml`.
- **Sunshine remote-desktop pairing** — `modules/desktop/sunshine.nix` is deployed
  and the service builds (NVENC confirmed: `h264/hevc/av1_nvenc` found).
  Outstanding: the one-time Moonlight pairing. The `sunshine` user unit binds
  `graphical-session.target`, so it only autostarts on a *fresh* Hyprland login (a
  lock/unlock won't trigger it); a stray manually-started instance currently holds
  the ports — `kill` it or reboot so systemd owns it. Then on the MacBook:
  `brew install --cask moonlight`, browse `https://workstation:47990` over the
  tailnet, set admin creds, PIN-pair, launch "Desktop", verify video + audio.
  Fallback if the NVIDIA KMS capture black-screens: set `capSysAdmin = false`
  (wlr capture — Hyprland is wlroots-based) and rebuild. Design + plan:
  `docs/superpowers/specs/2026-05-22-sunshine-remote-host-design.md`,
  `docs/superpowers/plans/2026-05-22-sunshine-remote-host.md`.

## Deferred (tracked, not currently worked)

- **Hetzner off-site restic** — second `services.restic.backups.<n>` repository per
  service (alongside the OneTouch `/mnt/backup` repo) targeting Hetzner Storage Box
  via SFTP. Per `docs/DESIGN.md` Layer 5 — irreplaceable data tier (`/home`,
  `/srv/share`, `@photos`, `@library`, Immich, Vaultwarden) gets off-site;
  less-critical state stays local-only. Bootstrap: provision Storage Box, sops
  secret for SSH key, mirror restic repos, verify monthly integrity check works
  remotely (prune cost matters more off-site). Last item from the
  first-run-wizards memory once *arr / Vaultwarden / Recyclarr all resolved
  2026-05-07.
- **Remaining stabilisation (apps)** — phases 1-3 + 6-prep landed 2026-05-08
  (CI + Renovate on all 4 app repos; zod validation on drinks-api; finnbydel →
  Astro + Hono, both stateful apps → Drizzle + bun:sqlite; @sentry SDKs wired,
  no-op without DSN). Remaining: phase 4 (static sites → Cloudflare Pages, removes
  3 attack surfaces from workstation), phase 5 (microvm.nix for drinks + finnbydel,
  kernel-level isolation for the stateful apps that stay on workstation). Sentry
  activation when operator provisions projects: (a) add 6 sops secrets
  `sentry-dsn-{heim,drinks-app,drinks-server,filmder,finnbydel-app,finnbydel-server}`
  to `secrets/apps.yaml`, (b) update each module's environment block:
  `SENTRY_DSN = config.sops.placeholder."sentry-dsn-..."` for runtime; for
  client-side builds, `VITE_SENTRY_DSN = ...` (Vite) or `SENTRY_DSN = ...` (Astro
  reads from process.env at build time).
- **Remaining SSO candidates** — second batch landed (Immich + Beszel native OIDC,
  Komga + calibre-web forward-auth). Still on the table:
  - **Native OIDC**: Komga could move from forward-auth to per-user OIDC if family
    members start wanting separate read-history; Spring Security OAuth2 config is
    verbose but doable.
  - **Skip / problematic**: Jellyfin (`media`) — mobile/TV clients use direct API
    tokens that bypass cookie-based forward-auth; native SSO is plugin-based with
    sharp historical edges, defer until plugin OIDC stabilizes. Radicale
    (`calendar`) — CalDAV clients can't follow forward-auth redirects, must stay on
    htpasswd. Glance/Gatus (`home`/`status`) — intentionally public dashboards.
    Syncthing (`sync`) — single-admin, low value. ntfy (`alert`) — push API path
    exemption ends up too permissive to be worth gating the web UI alone.
- **Lower-priority appliance candidates** — Glance (status dashboard), Radicale
  (CalDAV/CardDAV) could move to Pi following the same split-module pattern as
  beszel/ntfy. Light, gain failure independence at near-zero cost. Not
  load-bearing — pursue when Pi has spare cycles.
- **Batch C: generated docs from live config** — replace static "active services"
  + "host placement" + "snapshot policy" tables in DESIGN.md with `nix eval`-driven
  output (`scripts/render-docs.sh` → `docs/auto/*.md`, gated by a `docs-fresh`
  flake check). Eliminates a class of doc drift entirely (executable docs don't
  decay). Roughly 1-2h to land. The simpler `doc-coherence` check (now built, in
  `flake.nix`) covers the host-deferred drift class; this is the more ambitious
  follow-on.

## Idea backlog (no commitment)

- **UPS for workstation.** Single PSU is a non-goal for HA, but mid-write power
  loss on USB-attached IronWolf is a real recovery scenario. Cheap (~1500-3000 NOK
  for 600VA) insurance. No commitment yet.
- **Migration of IronWolf Pro from USB to internal SATA.** When SATA capacity
  becomes available (e.g., adding a SATA HBA via PCIe). USB enclosures have their
  own failure mode at the controller level.
- **`common-cpu-amd-pstate`** module on workstation hardware. Deferred from Phase 3.
- **NVIDIA Wayland edge cases** (multi-monitor VRR, suspend/resume nuances). Not
  blocking; document fixes in `hardware.nix` as they're encountered.
- **CUDA/Ollama drift.** Stable 25.11 had a CUDA 13 / 12.8 toolkit mismatch breaking
  some CUDA apps. Ollama bundles its own CUDA libs typically; verify Ollama works at
  install and pin nixpkgs version if it doesn't.
- **Home automation on the Pi.** Not currently planned; no concrete use case.
