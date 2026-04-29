# Project guide for Claude (and other agents)

You are working in a NixOS homelab flake with two live hosts:

- **nori-station** — workhorse. Bare metal x86_64 (Ryzen 5600X + RTX 5060 Ti). Runs Caddy, Authelia, all GPU/media/state-heavy services (Ollama, Jellyfin, Immich, *arr stack, Vaultwarden, etc.).
- **nori-pi** — appliance (Raspberry Pi 4, aarch64). Runs the observability + alerting + DNS plane that needs to survive station outages: Beszel hub, ntfy server, Gatus, Blocky in forwarder mode, Tailscale subnet router + exit node.

Read these before making changes:

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

## How to relocate a service to nori-pi

Pattern established by the beszel hub (commit b4499ee) and ntfy server (commit 9e0b2b6) migrations. Use when a service belongs in the appliance role (observability, alerting, DNS — see "What's the bias" → "Workhorse-by-default").

1. **Split the module** at `modules/server/<service>/{daemon,client}.nix`. The daemon part (the actual server) goes on Pi; the client/proxy part goes on every host that talks to it. Folder = coupling.
2. **Cross-host lanRoute** lives in the always-imported file (the client/notify side), wrapped in `lib.mkIf config.services.caddy.enable`. This way only the Caddy host (station) registers the route — Pi's Blocky stays in pure forwarder mode and the canonical service host owns the `*.nori.lan` map.
3. **Backend `host` field** in the lanRoute hardcodes Pi's tailnet IP (`100.100.71.3`). Yes, that couples the module to the current topology — accept the coupling; if the daemon ever moves back, it's one line.
4. **Per-host config** that varies by hostname (sops secret names, message templates) reads `config.networking.hostName` rather than introducing options.
5. **Hardware-specific FS gates** read existing registries (e.g., `config.nori.gpu.nvidiaDevices != [ ]` for NVIDIA `/dev/*` exposure) rather than per-service flags.
6. **State migration** is usually NOT worth it for non-load-bearing data (metrics, ephemeral caches). Daemon comes up empty on Pi and rebuilds from sops + first-use. Document the decision in the commit + the daemon module's header.
7. **`nori.backups.<n>.skip`** on the Pi-hosted daemon citing the anti-write storage posture (see `hosts/nori-pi/hardware.nix`). Don't add Pi-local restic until the planned fast-restore disk lands.
8. **Update `modules/server/default.nix`** (station's bundle) to import only the client side. Update `hosts/nori-pi/default.nix` to import both sides.
9. **Deploy order: Pi first** so the daemon is up before station's `services.<service>` config drops out and Caddy starts proxying cross-host.
10. **Verify end-to-end** via the canonical URL (e.g., `curl -fsS https://alert.nori.lan/v1/health`) — exercises DNS → Caddy → cross-host tailnet → daemon all in one call.

## How to operate

- **Primary dev host: nori-station** via Zed remote (Mac connects over SSH). Persistent clone at `~/Downloads/homelab` on the host. `~/Documents/nix-migration` on Mac is the laptop-side clone.
- Reach nori-station: `ssh nori-station` (alias if configured), `ssh nori@nori-station.saola-matrix.ts.net` (tailnet hostname), `ssh nori@100.81.5.122` (tailnet IP), or `ssh nori@192.168.1.181` (LAN).
- Reach nori-pi: `ssh nori@nori-pi.saola-matrix.ts.net` (tailnet hostname), `ssh nori@100.100.71.3` (tailnet IP), or `ssh nori@192.168.1.225` (LAN — static lease).
- **From Mac** the tailnet `.ts.net` hostnames don't resolve through normal DNS — use LAN IPs (`192.168.1.181` station, `192.168.1.225` Pi) for rsync/ssh. After Pi reboots its host key may regenerate; clear stale entries with `ssh-keygen -R <ip>` or pass `-o StrictHostKeyChecking=accept-new`. From a tailnet-attached host (i.e. Zed-remoted into station) the magicDNS hostnames work normally.
- Push from nori-station via SSH (`git@github.com:phibkro/homelab.git`). Mac uses HTTPS (default).
- **Justfile is local-by-default**: `just rebuild` builds whichever host you're sitting on (`nh os switch . -H $(hostname)`). From Mac — which isn't a NixOS host — recipes don't make sense locally; use the `remote` composition primitive instead: `just remote nori-station rebuild` rsyncs the working tree to `/tmp/nix-migration/` on nori-station + runs `just rebuild` there. Same pattern wraps any recipe: `just remote nori-station status`, `just remote nori-station logs sshd`, etc. Note: `just remote` uses the tailnet hostname; from Mac it may need replacing with direct rsync+ssh by LAN IP.
- Push to `origin/main` is the deploy boundary; any host can `git pull && just rebuild` (or `just deploy` to build from origin without touching the working tree).
- Long jobs go in the background — never block on them. Use `run_in_background: true`.
- Background `Bash` and `Agent` invocations always (per the operator's CLAUDE.md global rule).

## Current state

- **Channel**: `nixos-unstable` (2026-04-29 attempt to switch to 25.11 was activated then rolled back — three services broke on the downgrade because their state had been migrated forward by unstable: ntfy DB schema v15 vs 25.11's v13, Postgres VectorChord 1.1.1 vs 25.11's 0.5.3, plus an open-webui home-dir regression. See Outstanding "Migration to next stable" for the path forward).

- **Topology + service placement**:
  - **nori-station** (workhorse): Caddy (TLS + internal CA), Authelia (OIDC), Open WebUI, Ollama (CUDA), Jellyfin (NVENC OS-level live, web UI toggle pending), Immich (NVENC live + CUDA-ready ML with resource caps), full *arr stack (Sonarr/Radarr/Lidarr/Prowlarr/Bazarr/Jellyseerr/qBittorrent), Vaultwarden, Calibre-web, Komga, Radicale, Syncthing, Glance, Samba. Plus per-host telemetry: Beszel agent, Gatus, Blocky in self-hosted mode.
  - **nori-pi** (appliance): Beszel hub, ntfy server (`alert.nori.lan` reverse-proxied cross-host by station's Caddy), Gatus, Blocky in forwarder mode, Tailscale subnet router + exit node. Plus per-host telemetry: Beszel agent.
  - **Cross-host services use the split-module pattern** — daemon module on the host that runs it, client/proxy module on every host. See `modules/server/beszel/{hub,agent}.nix` and `modules/server/ntfy/{server,notify}.nix`. The cross-host Caddy lanRoute is gated `lib.mkIf config.services.caddy.enable` so the daemon-host's Blocky stays in pure forwarder mode.

- **nori-station hardware**: NixOS on bare metal (Ryzen 5600X, 32 GiB, RTX 5060 Ti, WD SN750 root + IronWolf media). Single user `nori`, passwordless wheel sudo, SSH key-only. Cooler repasted 2026-04-29 — sustained 12-thread load now ~72°C (was 95°C TJ_max throttling pre-repaste).
- **nori-pi hardware**: Pi 4 (8 GiB) on Samsung FIT 128GB USB. EEPROM `BOOT_ORDER=0xf41` (USB-then-SD). Anti-write storage posture in `hosts/nori-pi/hardware.nix`: no swap, `journald.Storage=volatile`, `vm.mmap_rnd_bits=18` aarch64 fixup. Means: services on Pi declare `nori.backups.<n>.skip = "..."` for now; restic-as-target is deferred until a real disk lands.

- **GPU access pattern**: services that need the GPU set `accelerationDevices` (or systemd `DeviceAllow`) from `config.nori.gpu.nvidiaDevices` — single source of truth in `modules/lib/gpu.nix`. Confirmed working: Ollama (CUDA, 14+ GiB used at idle with model loaded), Jellyfin (devices visible, web-UI flag still off), Immich (NVENC ready, ML on CPU).
- **Memory pressure handling**: `zramSwap.enable = true` in `modules/common/base.nix` — 16 GiB compressed swap on station. Required for nvcc/CUDA builds; previously caused OOM + host hang. Pi keeps swap off per anti-write posture.
- **Resource caps where it matters**: `immich-machine-learning.serviceConfig` has `CPUQuota=600%` + `MemoryMax=16G` — guard against the userspace-CPU-starvation pattern that wedged the host on 2026-04-28 (rtkit canary thread starved for 4+ minutes; full incident record in commit `c0a557d`).
- **Backups**: `nori.backups.<n>` (paths or skip) drives every restic job. OneTouch external is the local repo at `/mnt/backup` on station. Pi services skip until Pi gains its own disk. Hetzner off-site still on the roadmap.
- **OIDC**: `nori.lanRoutes.<n>.oidc = { ... }` auto-generates the Authelia client + sops secret + env-file template. Hash material lives only in sops (template config-filter expands at startup). `just oidc-key <name>` is the bootstrap.

## Outstanding

Tracked here only when actionable; routine done-work lives in `git log`.

- **Migration to next stable channel** — 2026-04-29 attempt failed because state had been forward-migrated by unstable's newer software (ntfy schema, VectorChord extension version) and couldn't be downgraded. When 26.05 stable cuts (~May 2026), services should be at-or-ahead of current unstable, so forward migration works. Pre-migration checklist: take fresh restic backups of `/var/lib/{immich,private/open-webui}` (ntfy state now on Pi and intentionally non-backed-up) for restore-and-init paths if a service barfs. Or accept overlay-pinned newer-than-stable for the few state-heavy services and treat the rest as stable. Full diagnosis of the failed attempt: commit b3650b0 → reverted in 48846ca.
- **Mac home-manager activation** — files staged at `~/.config/home-manager/`. Nix not yet installed (Determinate dropped Intel Mac Nov 2025; use upstream installer wrapped by `scripts/install-nix-mac.sh`). Run script → `nix run home-manager/master -- switch --flake ~/.config/home-manager#nori` → prune brew duplicates incrementally.
- **Jellyfin NVENC web UI toggle** — `https://media.nori.lan` → Dashboard → Playback → Hardware acceleration → Nvidia NVENC + tick codec boxes (h264/hevc/mpeg4/vp9/av1) → Save. OS-level GPU access is already live; this flips `<HardwareAccelerationType>` from `none` to `nvenc` in `/var/lib/jellyfin/config/encoding.xml`.
- **Immich CUDA ML overlay** — scaffold sits commented at the top of `modules/server/immich.nix`. Resource caps + fresh paste + zramSwap mean the rebuild is now tractable.
- **Beszel SSO consumer config** — PocketBase OAuth setup paused mid-flow; `modules/server/beszel/hub.nix` (file moved 2026-04-29) needs the reattach steps. Authelia client config can be added via `nori.lanRoutes.metrics.oidc = { ... }` once PocketBase's OAuth dance is plumbed.
- **Pi `localhost` → tailnet for beszel agent System entry** — manual Beszel UI fix: Settings → Systems → nori-station entry → change host from `localhost` to `nori-station.saola-matrix.ts.net`. Required because hub moved Pi-side; "localhost" now resolves to Pi.
- **Lower-priority appliance candidates**: Glance (status dashboard), Radicale (CalDAV/CardDAV) — could move to Pi following the same split-module pattern as beszel/ntfy. Light, gain failure independence at near-zero cost. Not load-bearing — pursue when Pi has spare cycles.
- **First-run wizards** for the *arr stack, Vaultwarden cloud-export migration, Hetzner off-site restic, Recyclarr — each module's header comment lists the steps.

## What's the bias

- **Correctness > simplicity > thoroughness > speed** for code quality decisions.
- **Declarative over imperative.** If a service's config can live in Nix (sops-managed where secret), prefer that. When tools fight code-as-config, switch tools (we replaced Uptime Kuma with Gatus for this reason).
- **Composable abstractions, not god modules.** `modules/lib/lan-route.nix` is the model: one option, multiple generators (Caddy + Blocky + Gatus). `modules/lib/backup.nix` and `modules/lib/gpu.nix` follow the same shape.
- **Workhorse-by-default, appliance-by-exception.** Services land on station unless they need to survive station's failure (observability, alerting, DNS) or are part of the network appliance role (subnet routing, exit node). Pi has 8 GiB and anti-write storage — every additional service competes with the observer role. The exception clause is "fate-sharing breaks the function," not "feels lightweight."
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

## On session end

When the user signals wrap-up ("ending session", "wrap up", "that's it for now"), do this so the next agent (likely you with zero context) lands cleanly:

1. **Push pending commits** — `git push origin main`. Local-only commits are invisible to a future agent that doesn't yet know about them.
2. **Refresh `CLAUDE.md`** if the session shifted reality:
   - Update the intro line if a host's status changed (planned → live, etc.).
   - Update "Current state" if topology, service placement, or hardware changed.
   - Prune "Outstanding" items that are done; add new ones the session surfaced.
   - If a *new pattern* was used twice or more, codify it as a "How to …" section (the b4499ee/9e0b2b6 cross-host service split → "How to relocate a service to nori-pi" is the precedent).
3. **Update auto-memory** if the session changed cross-conversation facts (host topology, user preferences, durable architectural decisions). Memory is in `~/.claude/projects/-Users-nori-Documents-nix-migration/memory/`. Don't duplicate what's already in CLAUDE.md — memory is for cross-project / user-personal facts.
4. **Verify clean state** — `git status` shows nothing in flight; both hosts are up (a quick `systemctl is-active <key-services>` on each is cheap insurance).
5. **End with a tight summary** — what changed, what was learned, what's the immediate next concrete thing — so the user (and the next agent reading the prior turn) gets oriented fast.

A new agent with zero context should be able to read `CLAUDE.md` + `git log --oneline -10` + the latest commits' bodies and know exactly where you left off. If they'd be confused, the wrap-up isn't done.
