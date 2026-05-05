# Project guide for Claude (and other agents)

You are working in a NixOS homelab flake with two live hosts:

- **nori-station** — workhorse. Bare metal x86_64 (Ryzen 5600X + RTX 5060 Ti). Runs Caddy, Authelia, all GPU/media/state-heavy services (Ollama, Jellyfin, Immich, *arr stack, Vaultwarden, etc.).
- **nori-pi** — appliance (Raspberry Pi 4, aarch64). Runs the observability + alerting + DNS plane that needs to survive station outages: Beszel hub, ntfy server, Gatus, Blocky in forwarder mode, Tailscale subnet router + exit node.

Read these before making changes:

1. **`docs/DESIGN.md`** — canonical architecture. The "why" lives here. v2.x.
2. **`docs/CONVENTIONS.md`** — established patterns. How modules are shaped, secrets are wired, services are added.
3. **`docs/gotchas.md`** — landmines. Read before touching: NVMe enumeration, Caddy CA trust, sops env files, openrsync flags, DynamicUser services.
4. **`.claude/skills/`** — recurring procedures (add a service, add a host, relocate to Pi, wrap session, on structural change). Auto-discovered when the trigger phrasing matches; load on demand. `docs/PROCEDURES.md` is the index.
5. `git log --oneline` — commit-by-commit narrative for context the docs don't catch.

## Hard rules

- **Code is the single-source-of-truth**, documentation is merely an approximation.
- **Never touch `nvme0n1`** without verifying the model string first via `/dev/disk/by-id/`. NVMe enumeration is unstable across reboots — `nvme0n1` was the NixOS root at install time, is now Windows. Disko configs target by-id paths for this reason.
- **Don't commit secrets.** Anything in `secrets/secrets.yaml` is sops-encrypted and safe. `.env` files are gitignored. Public certs (e.g., `modules/server/caddy-local-ca.crt`) are fine to commit.
- **Don't bypass the safety net.** Don't disable `services.restic.backups.*`, `services.btrbk.*`, OnFailure → ntfy alerts, or any other passive backend without naming why and how it'll be re-enabled.
- **Default-deny everywhere.** Network exposure, filesystem access, tailnet ports — services opt in to specific access, never wildcard.

## Procedures

Recurring procedures live as skills under `.claude/skills/`. They auto-discover when the user's intent matches the trigger description; manually invoke with `/<skill-name>`. See `docs/PROCEDURES.md` for the index. If you find yourself reasoning a procedure out from first principles, stop and let the skill expand.

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

- **Topology + service placement** (live list: `just ports` for Caddy-exposed services; each host's flat imports + `modules/server/*.nix` for the full set):
  - **nori-station** (workhorse): the HTTP entry plane (Caddy reverse proxy + Authelia OIDC), every GPU-bound service (Immich CUDA ML + NVENC, Ollama CUDA, Jellyfin NVENC), the *arr stack, and the long tail of state-bearing apps (password manager, calendar/contacts, ebook + comics + photo libraries, file sync, dashboard, SMB shares). Per-host telemetry: Beszel agent + Gatus + Blocky self-hosted.
  - **nori-pi** (appliance): the observability + alert plane that must survive station outages (Beszel hub, ntfy server, Gatus, Blocky forwarder) plus tailnet plumbing (subnet router + opt-in exit node). Per-host telemetry: Beszel agent.
  - **Cross-host services use the split-module pattern** — daemon module on the host that runs it, client/proxy module on every host. The cross-host Caddy lanRoute is gated `lib.mkIf config.services.caddy.enable` so the daemon-host's Blocky stays in pure forwarder mode. Live examples in `modules/server/{beszel,ntfy}/`.
  - **Cross-host references go through the topology registry** — `config.nori.hosts.<n>.tailnetIp`, never IP literals. Schema in `modules/lib/hosts.nix`; values in `flake.nix` `identityFor`. `readDir` over `./hosts/` drives both `nixosConfigurations` enumeration and the registry, so adding a host is "create the folder + add identity"; either omission fails eval. The `role` field (`workhorse` | `appliance`) drives the placement assertion in `modules/lib/backup.nix` (appliance hosts cannot use `paths`-based backups).

- **nori-station hardware**: NixOS on bare metal (Ryzen 5600X, 32 GiB, RTX 5060 Ti, WD SN750 root + IronWolf media). Single user `nori`, passwordless wheel sudo, SSH key-only. Cooler repasted 2026-04-29 — sustained 12-thread load now ~72°C (was 95°C TJ_max throttling pre-repaste).
- **nori-pi hardware**: Pi 4 (8 GiB) on Samsung FIT 128GB USB. EEPROM `BOOT_ORDER=0xf41` (USB-then-SD). Anti-write storage posture in `hosts/nori-pi/hardware.nix`: no swap, `journald.Storage=volatile`, `vm.mmap_rnd_bits=18` aarch64 fixup. Means: services on Pi declare `nori.backups.<n>.skip = "..."` for now; restic-as-target is deferred until a real disk lands.

- **GPU access pattern**: services that need the GPU set `accelerationDevices` (or systemd `DeviceAllow`) from `config.nori.gpu.nvidiaDevices` — single source of truth in `modules/lib/gpu.nix`. Confirmed working: Ollama (CUDA, 14+ GiB used at idle with model loaded), Jellyfin (devices visible, web-UI flag still off), Immich (NVENC ready, CUDA ML live).
- **Memory pressure handling**: `zramSwap.enable = true` in `modules/common/base.nix` — 16 GiB compressed swap on station. Required for nvcc/CUDA builds; previously caused OOM + host hang. Pi keeps swap off per anti-write posture.
- **Resource caps where it matters**: `immich-machine-learning.serviceConfig` has `CPUQuota=600%` + `MemoryMax=16G` — guard against the userspace-CPU-starvation pattern that wedged the host on 2026-04-28 (rtkit canary thread starved for 4+ minutes; full incident record in commit `c0a557d`).
- **Backups**: `nori.backups.<n>` (paths or skip) drives every restic job. OneTouch external is the local repo at `/mnt/backup` on station. Pi services skip until Pi gains its own disk. Hetzner off-site still on the roadmap.
- **OIDC**: `nori.lanRoutes.<n>.oidc = { ... }` auto-generates the Authelia client + sops secret + env-file template. Hash material lives only in sops (template config-filter expands at startup). `just oidc-key <name>` is the bootstrap.

## Outstanding

Tracked here only when actionable; routine done-work lives in `git log`.

- **Migration to next stable channel** — 2026-04-29 attempt failed because state had been forward-migrated by unstable's newer software (ntfy schema, VectorChord extension version) and couldn't be downgraded. When 26.05 stable cuts (~May 2026), services should be at-or-ahead of current unstable, so forward migration works. Pre-migration checklist: take fresh restic backups of `/var/lib/{immich,private/open-webui}` (ntfy state now on Pi and intentionally non-backed-up) for restore-and-init paths if a service barfs. Or accept overlay-pinned newer-than-stable for the few state-heavy services and treat the rest as stable. Full diagnosis of the failed attempt: commit b3650b0 → reverted in 48846ca.
- **Mac home-manager activation** — files staged at `~/.config/home-manager/`. Nix not yet installed (Determinate dropped Intel Mac Nov 2025; use upstream installer wrapped by `scripts/install-nix-mac.sh`). Run script → `nix run home-manager/master -- switch --flake ~/.config/home-manager#nori` → prune brew duplicates incrementally.
- **Jellyfin NVENC web UI toggle** — `https://media.nori.lan` → Dashboard → Playback → Hardware acceleration → Nvidia NVENC + tick codec boxes (h264/hevc/mpeg4/vp9/av1) → Save. OS-level GPU access is already live; this flips `<HardwareAccelerationType>` from `none` to `nvenc` in `/var/lib/jellyfin/config/encoding.xml`.
- **Beszel SSO consumer config** — PocketBase OAuth setup paused mid-flow; `modules/server/beszel/hub.nix` (file moved 2026-04-29) needs the reattach steps. Authelia client config can be added via `nori.lanRoutes.metrics.oidc = { ... }` once PocketBase's OAuth dance is plumbed.
- **Doc-coherence flake check** — close the variety gap: code-internal failure modes are well-covered by the existing checks suite (`flake.nix` `checks.${system}`); `no-stale-paths` is the only doc-touching detector and only catches path renames. Content-drift is uncovered. Concrete shape: a `runCommandLocal` derivation that fails if `flake.nix` declares `nori-pi` but README/DESIGN still contain "Pi deferred" / "DEFERRED" strings, or any future `<host>-as-state` / `<host>-as-flake` mismatch. Cheap; would have caught the README/DESIGN drift earlier this session. Lives in `flake.nix` `checks.${system}` alongside `forbidden-patterns`.
- **Batch C: generated docs from live config** — replace static "active services" + "host placement" + "snapshot policy" tables in DESIGN.md with `nix eval`-driven output (`scripts/render-docs.sh` → `docs/auto/*.md`, gated by a `docs-fresh` flake check). Eliminates a class of doc drift entirely (executable docs don't decay). Roughly 1-2h to land. Defer until the simpler doc-coherence check above proves itself useful.
- **Lower-priority appliance candidates**: Glance (status dashboard), Radicale (CalDAV/CardDAV) — could move to Pi following the same split-module pattern as beszel/ntfy. Light, gain failure independence at near-zero cost. Not load-bearing — pursue when Pi has spare cycles.
- **First-run wizards** for the *arr stack, Vaultwarden cloud-export migration, Hetzner off-site restic, Recyclarr — each module's header comment lists the steps.

## What's the bias

- **Correctness > simplicity > thoroughness > speed** for code quality decisions.
- **Declarative over imperative.** If a service's config can live in Nix (sops-managed where secret), prefer that. When tools fight code-as-config, switch tools (we replaced Uptime Kuma with Gatus for this reason).
- **Composable abstractions, not god modules.** `modules/lib/lan-route.nix` is the canonical example: one declarative option, multiple generators (Caddy vhost + Blocky DNS + Gatus monitor + Authelia client + sops template). The `nori.<...>` family in `modules/lib/` follows the same one-input-many-outputs shape.
- **Rule of three for abstractions.** Extract a function / module / macro only when three concrete uses exist. Two instances look like a pattern but are often coincidence; the third reveals the actual axis of variation. Premature abstraction locks in conventions before the variation is understood. Currently pending: cross-host service split has 2 instances (beszel hub, ntfy server) — wait for the 3rd before extracting `mkCrossHostService`.
- **Iterate-to-stable, then codify.** Novel patterns live in Cynefin's Complex domain — the right shape isn't visible upfront. Ship the simplest version that works, let the next constraint surface, iterate. Codify (as a "How to" / abstraction / convention) only after the shape stabilizes through use. The host registry was built three times in one session before stabilizing on `readDir` + `genAttrs` + `identityFor` — premature commitment to any of the earlier shapes would have been thrown away.
- **Workhorse-by-default, appliance-by-exception.** Services land on station unless they need to survive station's failure (observability, alerting, DNS) or are part of the network appliance role (subnet routing, exit node). Pi has 8 GiB and anti-write storage — every additional service competes with the observer role. The exception clause is "fate-sharing breaks the function," not "feels lightweight."
- **Code reviewers and future-you are the audience.** Comments explain *why* (especially when the obvious approach didn't work). Trace dependencies between modules in comments.

## Style for prose

- No hedging in commit messages or docs. Lead with the answer, justify after.
- Match the existing tone — terse, technical, no fluff. The operator (Philip) reads fast and pushes back on weak decisions.
- "Chat / ai / alert" naming convention: agnostic over branded. New services get function-named subdomains (`status.nori.lan` not `gatus.nori.lan`) unless the brand IS the identity.

## Quality gates

- `nix flake check` — standard Nix lints (statix, deadnix, format) plus the repo-specific guard derivations declared in `flake.nix` `checks.${system}`. Categories: eval-time module assertions, `every-service-has-<X>` pattern enforcement, `forbidden-patterns` anti-pattern grep, `no-stale-paths` rename guards. Run `nix flake show .#checks` for the live list.
- `nix fmt` — apply nixfmt.
- Pre-commit hook in `.githooks/pre-commit` runs `nix flake check` automatically when staged changes touch `.nix` files — enable once per clone with `git config core.hooksPath .githooks`. Skips gracefully if nix isn't on PATH (Mac case); GitHub Actions (`.github/workflows/check.yml`) catches the skipped commits on push. Bypass with `git commit --no-verify` for emergencies only.
- Conventions for new rules (when to encode as types vs assertions vs flake checks vs leave to review): `docs/CONVENTIONS.md` § "Enforcing conventions through code".

## Recurring procedures live as skills

Non-deterministic recurring procedures are extracted to `.claude/skills/` so the body loads only when the trigger fires (zero always-loaded context cost). Auto-discovery routes user intent to the right one:

| Skill | Triggers on |
|---|---|
| `/add-service` | "add <X>", "deploy <Y>", "set up <Z>" |
| `/add-host` | "add a host", "set up nori-<X>", "another machine" |
| `/relocate-to-pi` | "move <X> to Pi", "should survive station outages" |
| `/wrap-session` | "wrap up", "ending session", "that's it" |
| `/on-structural-change` | "we just landed <X>", post-commit doc-tier decision |

Adding a skill: `mkdir .claude/skills/<n> && $EDITOR .claude/skills/<n>/SKILL.md`. Frontmatter requires `description` (drives auto-discovery — put the key use case first). See https://code.claude.com/docs/en/skills for the canonical format. Existing skills are good templates.

The principle: prose for facts (always-loaded), skills for procedures (load on demand). When a CLAUDE.md section grows into a procedure with non-deterministic branches, extract it.
