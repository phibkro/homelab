---
summary: The forward plan — single home for outstanding work, deferred items, and
  the idea backlog. Routine done-work lives in `git log`; durable design lives in
  the tier-2 reference docs (TOPOLOGY/STORAGE/NETWORK/SERVICES/MODULES/…).
---

# Roadmap

The forward plan: actionable outstanding work, deferred-but-tracked items, and the idea backlog. **This is the single home for "what's next."** Items leave this file when done (folded into git log) or when explicitly killed.

## Outstanding (actionable)

- **Mac is on x86_64-darwin EOL clock.** Mac home-manager landed (`homeConfigurations.macbook` in `flake.nix`, content at `machines/macbook/home.nix`). Switch via `nix run home-manager/master -- switch --flake ~/Documents/nix-migration#macbook`. Nix installed via **Determinate Nix installer v3.12.2** (released 2025-11-05) — the last Determinate release with an `x86_64-darwin` binary; v3.12.3 (2025-11-10) dropped Intel Mac support. Future Intel-Mac installs need to pin v3.12.2 specifically or use upstream installer. **Nixpkgs 26.05 is the LAST release supporting x86_64-darwin** (surfaces in eval warnings). Decision needed when next stable ships: pin Mac to 26.05 indefinitely, migrate Mac off Nix, or replace hardware. Already adapted: prefer ad-hoc `nix shell` over `home.packages` for heavy compiles (Hydra cache is thin on x86_64-darwin); ghostty + utm stay on brew. Caddy local CA wired into Node clients via `home.sessionVariables.NODE_EXTRA_CA_CERTS` in `machines/macbook/home.nix`.

- **Jellyfin NVENC web UI toggle.** `https://media.nori.lan` → Dashboard → Playback → Hardware acceleration → Nvidia NVENC + tick codec boxes (h264/hevc/mpeg4/vp9/av1) → Save. OS-level GPU access is already live; this flips `<HardwareAccelerationType>` from `none` to `nvenc` in `/var/lib/jellyfin/config/encoding.xml`.

- **Sunshine remote-desktop pairing.** `modules/desktop/sunshine.nix` is deployed; service builds (NVENC confirmed: `h264/hevc/av1_nvenc` found). Outstanding: the one-time Moonlight pairing. The `sunshine` user unit binds `graphical-session.target`, so it only autostarts on a *fresh* Hyprland login (lock/unlock won't trigger); a stray manually-started instance currently holds the ports — `kill` it or reboot so systemd owns it. Then on the MacBook: `brew install --cask moonlight`, browse `https://workstation:47990` over tailnet, set admin creds, PIN-pair, launch "Desktop", verify video + audio. Fallback if NVIDIA KMS capture black-screens: set `capSysAdmin = false` (wlr capture — Hyprland is wlroots-based) and rebuild. Design + plan: `docs/superpowers/specs/2026-05-22-sunshine-remote-host-design.md`, `docs/superpowers/plans/2026-05-22-sunshine-remote-host.md`.

## Deferred (tracked, not currently worked)

- **Hetzner off-site restic** — second `services.restic.backups.<n>` repository per service (alongside the OneTouch `/mnt/backup` repo) targeting Hetzner Storage Box via SFTP. Per `STORAGE.md` § backup destinations — irreplaceable tier (`/home`, `/srv/share`, `@photos`, `@library`, Immich, Vaultwarden) gets off-site; less-critical state stays local-only. Bootstrap: provision Storage Box, sops secret for SSH key, mirror restic repos, verify monthly integrity check works remotely (prune cost matters more off-site).

- **Remaining stabilisation (personal apps).** Phases 1-3 + 6-prep landed 2026-05-08 (CI + Renovate on all 4 app repos; zod validation on drinks-api; finnbydel → Astro + Hono; stateful apps → Drizzle + bun:sqlite; @sentry SDKs wired, no-op without DSN). Remaining: phase 4 (static sites → Cloudflare Pages, removes 3 attack surfaces from workstation), phase 5 (microvm.nix for drinks + finnbydel, kernel-level isolation for stateful apps that stay on workstation). Sentry activation when operator provisions projects: add 6 sops secrets `sentry-dsn-{heim,drinks-app,drinks-server,filmder,finnbydel-app,finnbydel-server}` to `secrets/apps.yaml`; update each module's environment block.

- **Remaining SSO candidates.** Second batch landed (Immich + Beszel native OIDC, Komga + calibre-web forward-auth). Still on the table:
  - **Native OIDC:** Komga could move from forward-auth to per-user OIDC if family members start wanting separate read-history; Spring Security OAuth2 config is verbose but doable.
  - **Skip / problematic:** Jellyfin (mobile/TV clients bypass cookie-based forward-auth; native SSO plugin has sharp historical edges). Radicale CalDAV clients can't follow forward-auth redirects, must stay on htpasswd. Glance/Gatus are intentionally public. Syncthing is single-admin. ntfy push API path exemption ends up too permissive to be worth gating the web UI alone.

- **Lower-priority appliance candidates.** Glance (status dashboard), Radicale (CalDAV/CardDAV) could move to Pi following the same split-module pattern as beszel/ntfy. Light, gain failure independence at near-zero cost. Not load-bearing — pursue when Pi has spare cycles.

- **Batch C: generated docs from live config.** Replace static "active services" + "host placement" + "snapshot policy" tables in `SERVICES.md` / `TOPOLOGY.md` / `STORAGE.md` with `nix eval`-driven output (`scripts/render-docs.sh` → `docs/auto/*.md`, gated by a `docs-fresh` flake check). Eliminates a class of doc drift entirely (executable docs don't decay). Roughly 1–2h to land.

## Promotion register (from INVARIANTS.md)

The `[prose: unchecked]` claims worth mechanizing. Detail in INVARIANTS.md § promotion work-list:

- `disko-uses-by-id` — flake check grepping disko files for `/dev/nvme[0-9]` / `/dev/sda[0-9]?`.
- `function-named-subdomains` — flake check grepping route declarations against a brand denylist.
- `workhorse-vs-appliance-placement` — module assertion cross-checking service placement against host role.
- `systemd-execstart-resolves` — flake check resolving each `ExecStart` first-token to a closure path (the 2026-06-03 incident class).

## Idea backlog (no commitment)

- **UPS for workstation.** Single PSU is a non-goal for HA, but mid-write power loss on USB-attached IronWolf is a real recovery scenario. Cheap (~1500–3000 NOK for 600VA) insurance.
- **IronWolf Pro from USB to internal SATA.** When SATA capacity becomes available (PCIe HBA). USB enclosures have their own failure mode at the controller level.
- **`common-cpu-amd-pstate`** module on workstation hardware.
- **NVIDIA Wayland edge cases** (multi-monitor VRR, suspend/resume nuances). Not blocking; document fixes in `hardware.nix` as encountered.
- **CUDA/Ollama drift.** Ollama bundles its own CUDA libs; verify at install and pin nixpkgs version if it doesn't.
- **Home automation on the Pi.** No concrete use case currently.
