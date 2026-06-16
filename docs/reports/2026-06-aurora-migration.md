---
summary: Post-execution report for the aurora migration arc. Companion
  to the forward plan in `docs/plans/2026-06-11-aurora-migration.md`
  and ADRs 0002-0004. Captures HOW the phases actually landed —
  commit-grouped PR narrative, before/after architecture, memory
  entries added, operator follow-ups gated for later.
---

# Aurora migration — execution report

> **L3, historical.** Read this if you're catching up on how the
> aurora migration actually landed, or want the "PR-shaped narrative"
> behind the per-phase rows in the plan. Companion to the forward
> plan (`docs/plans/2026-06-11-aurora-migration.md`) and
> the three governing ADRs (`docs/decisions/000{2,3,4}-*.md`).

The arc spanned ~2026-06-04 through 2026-06-12. This report covers
the final push (2026-06-11 evening through 2026-06-12 afternoon)
during which **all 22 phases** in scope landed or had their
final blockers identified.

---

## Arc visualization

```
        ┌─────────────────────────────────────────────────────────────┐
        │  P10 photos+music rsync running ─────────────────────────►  │
        │  ┌──────┐                                                   │
        │  │ FIXES│ hyprlock DPMS bug + pi/restic race                │
        │  └──────┘                                                   │
        │           ┌──────┐                                          │
        │           │ P11  │ immich cutover (the last service)        │
        │           └──────┘                                          │
        │                  ┌─────────────────┐                        │
        │                  │ P12 prep + flip │ pi-central entry plane │
        │                  └─────────────────┘                        │
        │                                  ┌──────┐                   │
        │                                  │ P15  │ btrbk replication │
        │                                  └──────┘                   │
        │                                          ┌──────┐           │
        │                                          │ P18  │ NVIDIA fx │
        │                                          └──────┘           │
        └─────────────────────────────────────────────────────────────┘
        ▲                                                           ▲
        session start                                       session end
        family-tier on workstation                family-tier on aurora,
        single failure domain                     pi-central entry plane,
                                                  cold replica wired,
                                                  suspend unblocked
```

---

## Outcome at a glance

```
   BEFORE                                          AFTER
   ──────────────────────────────                  ──────────────────────────────
   client (any tailnet host)                       client (any tailnet host)
       │                                               │
       │ DNS query *.home.phibkro.org                  │ DNS query *.home.phibkro.org
       ▼                                               ▼
   workstation Blocky                              pi Blocky
       │ returns 192.168.1.181 (workstation)           │ returns 192.168.1.225 (pi)
       ▼                                               ▼
   workstation:443                                 pi:443
   ├─ Caddy ─►  workstation local backends         ├─ Caddy ─►  workstation:tailnet
   ├─ Authelia                                     ├─ Authelia
   └─ Blocky-authoritative                         └─ Blocky-authoritative
                                                                    │ also: aurora:tailnet
                                                                    ▼
                                                                 family-tier backends
```

Per-host role at session end (matches ADR-0002/0003 target architecture):

| Host | Role |
|---|---|
| **pi** | HTTP entry plane (Caddy + Authelia + Blocky-authoritative), LE wildcard cert on `*.home.phibkro.org`, observability, alerting |
| **aurora** | Family vault — `/mnt/family/*` (220 GB photos, 48 GB music, plus library/projects/home-videos/archive), 10 family-tier service backends, OneTouch backup target |
| **workstation** | Sleep-friendly compute — `*arr` stack, Ollama, Jellyfin, downloads, cold replica receiver for `/mnt/family/*`. No longer load-bearing for the family-tier surface. |
| **pavilion** | Agent quarantine + beszel-agent (live) |

---

## PR-by-PR breakdown

The 21 commits ahead of `origin/main` at session end group into 12
PR-shaped chunks. Each is independently revertable; presented in
chronological order so the dependencies read top-to-bottom.

### PR 1 — Pre-session staging

| | |
|---|---|
| Commits | `fd7699c`, `60b8649`, `04369a6` |
| Files | `home/desktop/hypr-lock.nix` (CADDY_AUTO_TRUST note), `modules/services/navidrome.nix`, `modules/services/backup/btrbk-replication.nix` |
| What | Carry-over from prior session: memory hygiene + comment fix, navidrome cutover Nix pre-staged, P15 sender module drafted. |

### PR 2 — Memory + doc drift sweep

| | |
|---|---|
| Commits | `2b3d7b7`, `e86920d` |
| Files | `docs/reference/topology.md`, `docs/reference/module-authoring.md`, `docs/roadmap.md`, 9 entries under `~/.claude/projects/.../memory/` |
| What | Path renames (`modules/server` → `modules/services`), drive-name corrections (`ironwolf` → `mp510`), URL updates (`*.nori.lan` → `*.home.phibkro.org`). ROADMAP gains a "do a full deep-scan post-migration" TODO. |

### PR 3 — Two standalone bug fixes

| | |
|---|---|
| Commits | `50a2e18`, `a983b0a` |

| Bug | Cause | Fix |
|---|---|---|
| hyprlock: monitor stays on at lock screen until typing password | Two listeners — lock at 10 min, DPMS off at 15 min. Returning during minute 10-14, DPMS off fires mid-keystroke. | DPMS off folded into the lock event itself; drop the separate listener. |
| restic alerts "repository already locked" nightly on caddy + authelia onetouch | Pi + workstation both wrote to same `:/caddy` + `:/authelia` paths on aurora chroot, raced at 03:00. | Pi onetouch target → `sftp:restic@aurora:/pi`; per-host namespace. |

### PR 4 — P11 immich cutover (the last family-tier service)

| | |
|---|---|
| Commit | `8800d5f` |
| Files | `modules/services/immich.nix`, `machines/workstation/default.nix` |

```
   BEFORE                                    AFTER
   ──────────────────────────────             ──────────────────────────────
   workstation                                workstation
   ├─ immich-server (127.0.0.1:2283)          └─ (no immich — closure -447 MB)
   ├─ postgresql (with immich + vchord)
   ├─ redis-immich                            aurora
   └─ /mnt/media/photos (220 GB)              ├─ immich-server (0.0.0.0:2283)
                                              ├─ postgresql + vchord
   aurora                                     ├─ redis-immich
   └─ immich-machine-learning (empty)         └─ /mnt/family/photos (220 GB)
```

Used the `/restore-pg-with-owner-fix` skill, which bakes in the
ALTER OWNER trap from
`~/.claude/projects/-srv-share-projects/memory/postgres-ownership-after-dump-restore.md`.
Verified: 14,164 assets + 1 user preserved, `{"res":"pong"}` through
pi's Caddy → aurora tailnet.

### PR 5 — P12 prep: open tailnet for cross-host proxying

| | |
|---|---|
| Commits | `c015a1a`, `ba38187`, `54a39d8` |
| Files | 13 modules under `modules/services/{arr/,}*.nix`, `modules/services/syncthing.nix` (guiAddress fix), `modules/services/backup/btrbk-replica-target.nix` (new), `machines/workstation/hardware.nix` (WoL) |

The structural prep needed before pi's Caddy could proxy *anything*
still on workstation:

```
                              tailnet
   pi:443 (Caddy)  ───────►   workstation:8989 sonarr     ┐
                              workstation:7878 radarr      │
                              workstation:8096 jellyfin    │  All ports
                              workstation:8384 syncthing*  │  now open on
                              workstation:11434 ollama     │  tailscale0
                              workstation:9696 prowlarr    │  via per-route
                              workstation:5055 jellyseerr  │  exposeOnTailnet
                              workstation:6767 bazarr      │
                              workstation:8686 lidarr      │
                              workstation:8083 qbittorrent ┘
                              
   * syncthing UI rebound from 127.0.0.1 → 0.0.0.0 via
     `services.syncthing.guiAddress` (the XML setting was
     overridden by --gui-address CLI flag, saved as
     `syncthing-gui-address-cli-override` memory entry)
```

P15 receiver module + WoL NIC config landed alongside since they
share the "workstation prep" theme.

### PR 6 — Pavilion sops onboarding

| | |
|---|---|
| Commit | `bd5326b` |
| Files | `.sops.yaml`, `machines/pavilion/default.nix`, `secrets/secrets.yaml`, `secrets/apps.yaml` |

Two gaps: `modules/services/beszel/agent.nix` was never imported on
pavilion (it's flat-imports), AND pavilion's age key wasn't in
`.sops.yaml`. Fixed both; pavilion's beszel-agent now active on
`:45876`. Operator follow-up: add pavilion as a system in the Beszel
UI on `pi:8090` to surface metrics.

### PR 7 — Hermes P12 prep

| | |
|---|---|
| Commit | `fccf922` |
| Files | `home/hermes/default.nix`, `modules/services/hermes.nix` |

Hermes refused non-loopback binds without OAuth. Trade-off taken:
`--insecure` flag — operator-tier audience makes tailnet membership
the actual gate (same pattern as qBittorrent/Stremio/Grafana). Caddy
still rewrites Host/Origin to `127.0.0.1:9119`, preserving the
GHSA-ppp5-vxwm-4cf7 mitigation against browser-DNS-rebinding for
clients that arrive via the Caddy path.

### PR 8 — P12 final cutover (the architectural flip)

| | |
|---|---|
| Commit | `0629326` |
| Files | `modules/common/default.nix`, `modules/services/authelia.nix`, `modules/services/default.nix` (hermes added to bundle), `machines/workstation/default.nix`, `machines/pi/default.nix` (gatus.exposeViaCaddy override dropped) |

The architectural flip itself, in one commit:

- `nori.lanIp = config.nori.hosts.pi.lanIp` in `modules/common/default.nix`
- `authelia.runsOn` flips workstation → pi
- workstation `caddy.enable = false` + `authelia.enable = false`
- Closure shrinks ~96 MB on workstation
- Operator action (Tailscale admin UI): DNS push order swapped — `home.phibkro.org` row from `100.81.5.122` (workstation) → `100.100.71.3` (pi)

Verified: 22 routes return 200/302/307 through pi's Caddy from every
tailnet host (workstation, pi, aurora, pavilion).

### PR 9 — Doc catch-up

| | |
|---|---|
| Commits | `eff279a`, `3992544`, `b276da7`, `0ad8e3d` |
| Files | `docs/plans/2026-06-11-aurora-migration.md`, `docs/roadmap.md`, `docs/decisions/0003-pi-central-entry-plane.md`, `docs/decisions/0004-letsencrypt-on-home-phibkro-org.md`, `modules/services/jellyfin.nix` |

- ADR-0003 gets a second addendum recording the cutover landed; the earlier "reverted state" caveat is superseded
- ADR-0004 diagram updated: Caddy on pi, not workstation
- ROADMAP refreshed; aurora-migration plan walked through P10–P12
- Jellyfin NVENC UI state codified as a comment block next to the module — Jellyfin stores hardware-accel config in `encoding.xml`, not a Nix option, so the comment is the only place the "intended UI state" can live

### PR 10 — P15 wired live

| | |
|---|---|
| Commit | `2877267` |
| Files | `modules/services/backup/btrbk-replication.nix`, `modules/services/backup/btrbk-replica-target.nix`, `machines/aurora/default.nix`, `machines/workstation/default.nix`, `secrets/secrets.yaml` |

```
   aurora                              workstation
   ┌────────────────────────┐          ┌────────────────────────┐
   │ /mnt/family/photos     │  ──┐     │ /mnt/family-replica/   │
   │ /mnt/family/archive    │    │     │   ├── @-photos         │
   │ /mnt/family/home-videos│    │     │   ├── @-archive        │
   │ /mnt/family/library    │    │     │   ├── @-home-videos    │
   │ /mnt/family/projects   │    │     │   ├── @-library        │
   └────────────────────────┘    │     │   └── @-projects       │
                                 │     └────────────────────────┘
            daily btrbk          │              ▲
            send | ssh           │              │
            zstd | btrfs receive └──────────────┘
```

Key gotcha solved: the sops secret was root-owned, but the unit
runs as `User=btrbk` (uid 991). Owner=btrbk:btrbk fixed it. The
failure mode is "ssh non-interactive auth: Permission denied
(publickey)" which btrbk surfaces as "Failed to fetch subvolume
detail" rather than the underlying ssh error — costs a few minutes
of misdirection.

Target shape: per-subvolume `target ssh://<workstation>/mnt/family-
replica/<X>` rather than one parent target. MP510's disko layout
mounts each `@family-replica-<X>` subvol independently — there's no
single btrfs filesystem at `/mnt/family-replica` that btrbk could
treat as a shared receive directory.

### PR 11 — P18 NVIDIA suspend fix

| | |
|---|---|
| Commit | `93a18f8` |
| Files | `machines/workstation/hardware.nix` |

Root cause of the 2026-06-10 s2idle resume hang documented in
`e12d34d`: `hardware.nvidia.powerManagement.enable = false` meant the
NVIDIA kernel module loaded without:

- `NVreg_PreserveVideoMemoryAllocations=1` — saves VRAM contents
  across s2idle so the compositor has something coherent to render
  after resume.
- `NVreg_UseKernelSuspendNotifiers=1` — the in-kernel notifier path
  used by driver 595+ with the open module.

With `powerManagement.enable = true` and driver `595.71.05` + `open
= true`, the NixOS module sets `kernelSuspendNotifier = true` by
default, which adds both params to `/etc/modprobe.d/nixos.conf`.
The "no keyboard/mouse input" half of the symptom is the secondary
effect of the compositor hanging — input still flowed but had
nowhere to render to.

**Reboot required.** Kernel module params take effect at module
load time; the currently-loaded NVIDIA module still has the
pre-change params.

### PR 12 — Final doc sync

| | |
|---|---|
| Commit | `3ae2576` |
| Files | `docs/plans/2026-06-11-aurora-migration.md` |

P15/P18/P19/P20 rows updated to carry explicit test plans + gating
relationships so the next agent doesn't try them out of order.

---

## Memory entries added during the arc

```
~/.claude/projects/-srv-share-projects/memory/
├── rsync-destination-service-ownership.md
│   USE WHEN bulk-rsyncing into a host where the consuming service
│   is already running — service ensures own dir ownership at
│   startup, rsync-user loses write perms mid-stream
├── scripted-networking-link-files-inert.md
│   USE WHEN a networking.interfaces.<n>.<opt> Nix option emits a
│   systemd-networkd .link file but the live NIC doesn't reflect it;
│   scripted networking (useDHCP = true) doesn't process .link files
└── syncthing-gui-address-cli-override.md
    USE WHEN services.syncthing.settings.gui.address doesn't
    propagate; nixpkgs hardcodes --gui-address as a CLI flag that
    overrides the XML
```

---

## What was left at session end

```
                            21 commits ahead of origin (held; not pushed)
                                        │
                            ┌───────────┴───────────┐
                            │                       │
                       OPERATOR-DRIVEN          AGENT-DOABLE LATER
                       reboot workstation       (none urgent — the
                            │                    arc is structurally
                       ┌────┴────┐               complete)
                       │ P18     │ verify suspend resumes cleanly
                       │ P19     │ wakeonlan magic packet test
                       │ P20     │ re-add hypridle 30-min listener
                       └─────────┘
```

P18/P19/P20 became a single operator sitting after a convenient
suspend window opens. See the corresponding rows in the plan doc for
the exact test commands.

---

## See also

- `docs/plans/2026-06-11-aurora-migration.md` — the forward plan with per-phase tables, validation gates, reversibility ladder. Tracks the "what" and the "when".
- `docs/decisions/0002-aurora-as-family-vault.md` — ADR establishing the per-host roles + replication topology.
- `docs/decisions/0003-pi-central-entry-plane.md` — ADR pivoting the HTTP entry plane from aurora to pi.
- `docs/decisions/0004-letsencrypt-on-home-phibkro-org.md` — ADR moving from internal CA to LE wildcard on a real domain.
- `git log --grep="P11\|P12\|P15\|P18" --oneline` — the chronological view, no narrative grouping.
