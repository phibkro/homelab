# Project guide for Claude (and other agents)

You are working in a NixOS homelab flake. Single host live (nori-station); nori-pi planned. Read these before making changes:

1. **`docs/DESIGN.md`** — canonical architecture. The "why" lives here. v2.x.
2. **`docs/CONVENTIONS.md`** — established patterns. How modules are shaped, secrets are wired, services are added.
3. **`docs/gotchas.md`** — landmines. Read before touching: NVMe enumeration, Caddy CA trust, sops env files, openrsync flags, DynamicUser services.
4. `git log --oneline` — commit-by-commit narrative for context the docs don't catch.

## Hard rules

- **Never touch `nvme0n1`** without verifying the model string first via `/dev/disk/by-id/`. NVMe enumeration is unstable across reboots — `nvme0n1` was the NixOS root at install time, is now Windows. Disko configs target by-id paths for this reason.
- **Don't commit secrets.** Anything in `secrets/secrets.yaml` is sops-encrypted and safe. `.env` files are gitignored. Public certs (e.g., `modules/server/caddy-local-ca.crt`) are fine to commit.
- **Don't bypass the safety net.** Don't disable `services.restic.backups.*`, `services.btrbk.*`, OnFailure → ntfy alerts, or any other passive backend without naming why and how it'll be re-enabled.
- **Default-deny everywhere.** Network exposure, filesystem access, tailnet ports — services opt in to specific access, never wildcard.

## How to add a new service

1. Create `modules/server/<service>.nix` (loose) or land inside an existing tightly-coupled folder like `modules/server/arr/`. Folders signal coupling; flat = independent.
2. Enable the service module.
3. Apply default-deny FS hardening (`ProtectHome = lib.mkForce true;` + `TemporaryFileSystem` + `BindReadOnlyPaths`; full snippet in `docs/CONVENTIONS.md`).
4. Declare `nori.lanRoutes.<name> = { port = N; monitor = { }; };` for HTTPS access via Caddy + auto-monitoring.
5. Declare `nori.backups.<name>` — either `paths = [ ... ]` for what to back up, or `skip = "<reason>"` for explicit opt-out. Schema requires one or the other; `every-service-has-backup-intent` flake check fails the build if you forget. DynamicUser services point at `/var/lib/private/<name>` (the symlink target, not the symlink itself).
6. Append the new file to `modules/server/default.nix` (loose) or the relevant cluster's `default.nix` (e.g. `modules/server/arr/default.nix`). Coupled clusters import their own siblings via `default.nix`; loose services land in the top-level imports list.
7. If the service needs secrets: `sops secrets/secrets.yaml` (env-file format `KEY=VALUE` if consumed via `EnvironmentFile`).
8. If the service needs SSO: `just oidc-key <name>` → paste raw + hash into sops → declare `nori.lanRoutes.<name>.oidc = { clientName; redirectPath; };` in the same module → wire `EnvironmentFile = config.sops.templates."oidc-<name>-env".path;` + `SupplementaryGroups = [ "keys" ];` on the systemd unit. See `docs/CONVENTIONS.md` "Authelia OIDC pattern".
9. If the service needs GPU access: set its `accelerationDevices` (or systemd `DeviceAllow`) to `config.nori.gpu.nvidiaDevices`. The list lives in `modules/lib/gpu.nix`.
10. `just rebuild` (from Mac) or `nh os switch . -H nori-station` (from the host).
11. Commit (Conventional Commits — type + scope + tight summary).

## How to operate

- **Primary dev host: nori-station** via Zed remote (Mac connects over SSH). Persistent clone at `~/Downloads/homelab` on the host. `~/Documents/nix-migration` on Mac is the laptop-side clone.
- Reach nori-station: `ssh nori-station` (alias if configured), `ssh nori@nori-station.saola-matrix.ts.net` (tailnet hostname), `ssh nori@100.81.5.122` (tailnet IP), or `ssh nori@192.168.1.181` (LAN).
- Push from nori-station via SSH (`git@github.com:phibkro/homelab.git`). Mac uses HTTPS (default).
- Rebuild from the host: `cd ~/Downloads/homelab && nh os switch . -H nori-station` (in place, no rsync).
- Rebuild from Mac: `just rebuild` (rsyncs working tree to `/tmp/nix-migration/` then `nh os switch`).
- Push to `origin/main` is the deploy boundary; nori-station can `git pull` and rebuild from there.
- Long jobs go in the background — never block on them. Use `run_in_background: true`.
- Background `Bash` and `Agent` invocations always (per the operator's CLAUDE.md global rule).

## Current state

- **nori-station**: NixOS on bare metal (Ryzen 5600X, 32 GiB, RTX 5060 Ti, WD SN750 root + IronWolf media). Single user `nori`, passwordless wheel sudo, SSH key-only.
- **nori-pi**: deferred — no NixOS-bootable USB SSD on hand. Existing Pi runs PiOS imperatively if DNS or restic-target needed in the interim.
- **Active services**: Caddy (TLS + internal CA), Authelia (OIDC), Open WebUI, Ollama (CUDA), Jellyfin (NVENC OS-level live, web UI toggle pending), Immich (NVENC live + CUDA-ready ML with resource caps), Beszel hub, Gatus, ntfy, Blocky, full *arr stack (Sonarr/Radarr/Lidarr/Prowlarr/Bazarr/Jellyseerr/qBittorrent), Vaultwarden, Calibre-web, Komga, Radicale, Syncthing, Glance, Samba.
- **GPU access pattern**: services that need the GPU set `accelerationDevices` (or systemd `DeviceAllow`) from `config.nori.gpu.nvidiaDevices` — single source of truth in `modules/lib/gpu.nix`. Confirmed working: Ollama (CUDA, 14+ GiB used at idle with model loaded), Jellyfin (devices visible, web-UI flag still off), Immich (NVENC ready, ML on CPU).
- **Memory pressure handling**: `zramSwap.enable = true` in `modules/common/base.nix` — 16 GiB compressed swap. Required for nvcc/CUDA builds; previously caused OOM + host hang.
- **Resource caps where it matters**: `immich-machine-learning.serviceConfig` has `CPUQuota=600%` + `MemoryMax=16G` — guard against the userspace-CPU-starvation pattern that wedged the host on 2026-04-28 (rtkit canary thread starved for 4+ minutes; full incident record in commit `c0a557d`).
- **Backups**: `nori.backups.<n>` (paths or skip) drives every restic job. OneTouch external is the local repo at `/mnt/backup`. Hetzner off-site still on the roadmap.
- **OIDC**: `nori.lanRoutes.<n>.oidc = { ... }` auto-generates the Authelia client + sops secret + env-file template. Hash material lives only in sops (template config-filter expands at startup). `just oidc-key <name>` is the bootstrap.

## Outstanding

Tracked here only when actionable; routine done-work lives in `git log`.

- **nori-pi setup** — gated on USB SSD hardware. When unblocked, mutual observability is the design: nori-pi runs its own minimal Gatus + ntfy probing nori-station's services; nori-station's existing Gatus + ntfy gains probes for nori-pi. Each host's failure is alerted by the *other*, eliminating the single-host-down blind spot the 2026-04-28 incident exposed (Blocky and ntfy went down together, no alert fired). Also picks up: Blocky as primary DNS (per DESIGN), restic-target for fast local restore, Tailscale subnet router + opt-in exit node.
- **Jellyfin NVENC web UI toggle** — `https://media.nori.lan` → Dashboard → Playback → Hardware acceleration → Nvidia NVENC + tick codec boxes (h264/hevc/mpeg4/vp9/av1) → Save. OS-level GPU access is already live; this flips `<HardwareAccelerationType>` from `none` to `nvenc` in `/var/lib/jellyfin/config/encoding.xml`.
- **Immich CUDA ML overlay** — scaffold sits commented at the top of `modules/server/immich.nix`. Resource caps now contain the next attempt. zramSwap handles the build's memory pressure.
- **Beszel SSO consumer config** — PocketBase OAuth setup paused mid-flow; `modules/server/beszel.nix` has the reattach instructions in a comment block.
- **First-run wizards** for the *arr stack, Vaultwarden cloud-export migration, Hetzner off-site restic, Recyclarr — each module's header comment lists the steps.

## What's the bias

- **Correctness > simplicity > thoroughness > speed** for code quality decisions.
- **Declarative over imperative.** If a service's config can live in Nix (sops-managed where secret), prefer that. When tools fight code-as-config, switch tools (we replaced Uptime Kuma with Gatus for this reason).
- **Composable abstractions, not god modules.** `modules/lib/lan-route.nix` is the model: one option, multiple generators (Caddy + Blocky + Gatus). `modules/lib/backup.nix` and `modules/lib/gpu.nix` follow the same shape.
- **Code reviewers and future-you are the audience.** Comments explain *why* (especially when the obvious approach didn't work). Trace dependencies between modules in comments.

## Style for prose

- No hedging in commit messages or docs. Lead with the answer, justify after.
- Match the existing tone — terse, technical, no fluff. The operator (Philip) reads fast and pushes back on weak decisions.
- "Chat / ai / alert" naming convention: agnostic over branded. New services get function-named subdomains (`status.nori.lan` not `gatus.nori.lan`) unless the brand IS the identity.

## Quality gates

- `nix flake check` — eval (with module assertions) + statix + deadnix + nixfmt format check + `forbidden-patterns` (no inline pbkdf2 hashes, no caddy/blocky bypass) + `every-service-has-backup-intent`.
- `nix fmt` — apply nixfmt.
- Pre-commit hook in `.githooks/pre-commit` runs `nix flake check` automatically when staged changes touch `.nix` files — enable once per clone with `git config core.hooksPath .githooks`. Skips gracefully if nix isn't on PATH (Mac case); GitHub Actions (`.github/workflows/check.yml`) catches the skipped commits on push. Bypass with `git commit --no-verify` for emergencies only.
- Conventions for new rules (when to encode as types vs assertions vs flake checks vs leave to review): `docs/CONVENTIONS.md` § "Enforcing conventions through code".

## On first turn

If the user's opening is open-ended ("where are we?", "what now?"), respond with one paragraph of status, the immediate next concrete action, and at most two open questions. Don't dump the roadmap. They're already the architect; you're implementing alongside.
