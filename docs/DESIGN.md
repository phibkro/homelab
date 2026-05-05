# nori — Home Lab Design Document (v2)

**Status:** Canonical. Supersedes DESIGN.md v1.
**Owner:** Philip
**Last updated:** April 27, 2026
**Verification window:** `nixos-unstable` channel (currently 26.05-pre); kernel 6.18 LTS or 6.19; NVIDIA driver 580.x via `nvidiaPackages.production`; Hyprland on Wayland with explicit-sync; btrfs single-device mature; restic + Hetzner Storage Box well-trodden path; `services.beszel.{hub,agent}` confirmed available.

**Channel rationale:** unstable, not stable, because Blackwell support requires NVIDIA driver 575+ and stable 25.11 lags. Pinned via `flake.lock`; treat unstable + lockfile-pinning as the de-facto stable channel for this lab. Re-pin deliberately, not on every `nix flake update`.

---

## Overview

A two-host home lab on a single residential network, built around three principles:

- **Declarative reproducibility.** Full system state expressible in version-controlled config; bare-metal rebuild is a documented procedure, not a novel undertaking.
- **Default-deny exposure.** Services opt into accessibility; nothing is exposed by default. The filesystem is not a network share except where explicitly designated.
- **Policy proportional to data value.** Re-derivable data gets minimal protection; service state gets daily snapshots and local backup; irreplaceable data gets snapshots, local backups, and off-site backups.

The lab serves a small household (Philip plus a handful of family members) and is operated entirely from a laptop via Tailscale. Physical console access is limited to installation and recovery.

---

## Goals

- **Reproducibility.** All system configuration in a single Git-tracked flake.
- **Remote-first operation.** Daily interaction via SSH and `nh` from the laptop, mediated by Tailscale.
- **Data durability proportional to value.**
- **Composable, minimal tooling.** Native NixOS modules first, containers as fallback, no orchestration layer.
- **Multi-OS coexistence without compromise.** Windows preserved on its own NVMe; UEFI multi-boot.
- **Multi-user services without multi-user OS.** One Linux user (Philip); per-service auth for family.

## Non-goals

- High availability. Single host, single PSU, single ISP.
- Public internet hosting. Tailscale-first; Cloudflare Tunnel + Cloudflare Access only when Tailscale friction emerges.
- Multi-machine orchestration beyond two hosts.
- Multi-tenant OS isolation.

## RTO targets

| Failure | Target | Mitigation |
|---|---|---|
| Bad config | <15 min | NixOS rollback (atomic generations) |
| Single file deletion | <15 min | btrbk snapshot restore |
| Service corruption | <1 hour | Stop service, restore subvolume snapshot, restart |
| Pi total failure | <2 hours | Spare USB SSD or reflash from flake |
| Root drive failure (main host) | <1 day | Reinstall via disko + flake, restic restore from Pi |
| Media drive failure | <1 day for services, days for media data | Service config restored fast; bulk media restore is bandwidth-bound |
| Whole-machine loss | Days+ | Hardware procurement is the bottleneck |

---

## Architecture

The lab decomposes into seven layers.

### Layer 1: Hosts and hardware

**`nori-station` (primary host)**
- AMD Ryzen 5600X, 32GB DDR4, RTX 5060 Ti 16GB (Blackwell)
- WD Black SN750 1TB NVMe → NixOS root (btrfs, six subvolumes, label `nixos`, disko-managed)
- Corsair Force MP510 960GB NVMe → Windows (preserved, untouched, multi-boot via UEFI)
- Seagate IronWolf Pro 4TB, USB → media storage (btrfs, five subvolumes, label `ironwolf-storage`, disko-managed; reformatted from exfat in Phase 2)
- Roles: AI inference (32B-class models comfortably; 70B models tight at 32GB and likely paged to swap), media streaming, photo management, file storage, occasional desktop workstation
- *Disambiguate disks by model + by-id, not `/dev/nvmeN` — see "Permanent constraints".*

**`nori-pi` (appliance) — LIVE**
- Raspberry Pi 4 8GB
- Samsung FIT 128GB USB stick → NixOS root (aarch64, sd-image-aarch64 generation, USB-then-SD boot order via EEPROM `BOOT_ORDER=0xf41`)
- Anti-write storage posture: `swapDevices = []`, `journald.Storage=volatile`, `vm.mmap_rnd_bits=18` aarch64 fixup. SD card wear is the #1 Pi failure mode; volatile journald + no swap mitigate.
- Roles (live): observability hub (Beszel), alert plane (ntfy server), network DNS adblock (Blocky in forwarder mode), synthetic monitoring (Gatus), Tailscale subnet router + exit node (opt-in per device).
- Roles (planned): local restic backup target for nori-station fast restore — deferred until a real disk replaces the FIT (the anti-write posture rules out daily restic to flash).
- Cross-host services (Beszel hub, ntfy server) are reverse-proxied via station's Caddy at `metrics.nori.lan` / `alert.nori.lan` — see CLAUDE.md "How to relocate a service to nori-pi" for the split-module pattern.

**`vm-test` (transient, for VM dry-run)**
- UTM virtual machine on laptop
- NixOS via the same flake, used to validate config changes before applying to bare metal
- On the tailnet for the duration of testing; deleted after Phase 4 validation
- Mentioned for completeness; not part of the long-term topology

**Failure domain independence:** the two persistent hosts share no storage, no power supply, no critical dependency in the boot path. Either host's failure does not block the other.

### Layer 2: Boot and OS

UEFI multi-boot on nori-station. NixOS as primary OS, Windows preserved on its own NVMe, OS selection via firmware boot menu. Each OS owns its drive completely; no shared bootloader.

`systemd-boot` as the bootloader for NixOS (default for UEFI on NixOS, handles btrfs subvolumes natively). UEFI NVRAM persists boot entries on the Gigabyte board; if first boot fails to register the entry (a known UTM quirk that may not appear on real hardware), recovery is `bootctl install` from a chroot.

**Channel:** `nixos-unstable`, pinned via flake.lock. Re-pin on a deliberate cadence (monthly or when a needed feature lands), not on every `nix flake update`.

**NVIDIA driver path:**

```nix
hardware.nvidia = {
  modesetting.enable = true;
  open = true;  # Required for Blackwell; also required by nixpkgs nvidia module for driver 555+
  package = config.boot.kernelPackages.nvidiaPackages.production;  # 595.58.03 as of Phase 6 (was 580.x at Phase 4 install)
  nvidiaSettings = true;
};
```

**Known gotchas:**

- Driver 580.119.02 had a build failure on kernel 6.19 (vm_area_struct API change). Resolved upstream — by Phase 6 the production driver is 595.58.03 with kernel 6.18 LTS, no manual pinning needed. The fallback ladder below remains documented for future regressions.
- Fallback ladder if `production` doesn't work first try: `production` → `beta` → `latest` → explicit `mkDriver` with a known-good version. This ladder is documented in the install runbook.
- `legacy_580` exists as a pinned-to-580 attribute, useful as a stable fallback that won't drift.

### Layer 3: Storage

Btrfs everywhere on Linux. Mount options: `compress=zstd:3` and `noatime`.

#### nori-station root (nvme0n1) — disko-managed

Subvolume layout, applied by disko during Phase 4 install:

| Subvolume | Mount | Snapshotted | Notes |
|---|---|---|---|
| `@` | `/` | Yes (before each rebuild via btrbk) | System root |
| `@home` | `/home` | Hourly + daily | User data |
| `@nix` | `/nix` | Never | Re-derivable from flake |
| `@var-lib` | `/var/lib` | Daily | Service state |
| `@srv-share` | `/srv/share` | Daily | Family-shared documents and ad-hoc dumping ground |
| `@snapshots` | `/.snapshots` | N/A | Snapshot target subvolume |

`@var-lib` separation lets service-state churn snapshot on its own cadence without polluting `@` snapshots. `@srv-share` is the explicit shared path referenced in the access matrix; documents go here when they're meant to be Samba-accessible from multiple devices.

#### nori-station media (sda, IronWolf Pro) — Phase 2

Reformatted to btrfs **after** Phase 4. Until then, the IronWolf is mounted read-only as exfat at `/mnt/media-legacy/` and Jellyfin/Immich either don't run yet or read from there. Disko config exists but is not applied during Phase 4.

Target subvolume layout (Phase 2):

| Subvolume | Mount | Snapshot | Local backup (OneTouch) | Off-site backup (Hetzner) |
|---|---|---|---|---|
| `@streaming` | `/mnt/media/streaming` | Weekly, keep 2 | No | No |
| `@photos` | `/mnt/media/photos` | Daily, keep 14 + monthly, keep 12 | Yes | Yes |
| `@home-videos` | `/mnt/media/home-videos` | Weekly, keep 4 | Yes | Yes |
| `@projects` | `/mnt/media/projects` | Weekly, keep 4 | Yes | Yes |
| `@library` | `/mnt/media/library` | Daily, keep 14 | Yes | Yes |
| `@archive` | `/mnt/media/archive` | Weekly, keep 4 | Yes | No (legacy machine backups; not off-site-worthy) |
| `@snapshots` | `/mnt/media/.snapshots` | N/A | N/A | N/A |

`@streaming` holds re-derivable content (auto-grabbed by the *arr stack: movies/shows/music + qBittorrent download staging). `@library` holds curated content the user assembled by hand (books, comics) — distinct content type from `@projects` (work products), same backup tier. `@archive` holds historical/cold data (legacy machine backups migrated off the OneTouch when it became the restic target).

#### nori-pi storage

`@` on USB SSD (root). USB HDD mounted at `/mnt/backup` holds the restic repository for nori-station's irreplaceable data and service state. Restic encrypts client-side, so the HDD's filesystem choice doesn't matter for security; ext4 is the boring default.

#### Database-on-btrfs CoW interaction

Postgres and other databases write in a copy-on-write-unfriendly pattern. Two interactions to handle, separately:

**Write-performance interaction (per-directory `chattr +C` or `nodatacow`).** Database directories should have CoW disabled to avoid write amplification. For Immich's Postgres in `/var/lib/immich/database`, set the directory `+C` before initialization, or place service state on a subvolume mounted with `nodatacow`. This is a *performance* fix, not a backup-consistency fix.

**Backup-consistency interaction (logical dumps before backup).** Filesystem-level snapshot of a running database produces inconsistent state. Backup correctness requires a logical dump (`pg_dump` for Postgres, `.backup` API for SQLite) before restic touches the data. Pattern in Layer 5.

### Layer 4: Networking and access control

Three network zones with default-deny posture:

- **Localhost.** Services bind here unless explicitly exposed.
- **Tailnet (trusted network).** Personal devices and family members. Most services exposed here. SSH, SSHFS, Samba, direct service ports are tailnet-only.
- **Public internet (Phase 4 deferred).** Specific HTTP services exposed via Cloudflare Tunnel at named subdomains under `phibkro.org`, with auth at the edge via Cloudflare Access (free tier, email magic links). Triggered when Tailscale friction emerges, not by schedule.

**Implementation pattern:** services use `openFirewall = false` and access flows through Caddy at `https://<name>.nori.lan` (see "LAN routing abstraction" below). Direct backend ports stay closed on tailnet by default; opt in per-service via `nori.lanRoutes.<name>.exposeOnTailnet = true` only when truly needed.

```nix
# Don't do this anymore — direct port exposure:
# networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8096 ];

# Do this — single declaration generates Caddy vhost + DNS + monitor:
nori.lanRoutes.media = { port = 8096; monitor = { }; };
```

The only globally-open tailnet ports today are `80 + 443` (Caddy) and `445` (Samba — not HTTP, can't go through Caddy).

#### LAN routing abstraction (`nori.lanRoutes`)

`modules/lib/lan-route.nix` defines a single NixOS option that generates *three* things per service: Caddy reverse-proxy vhost, Blocky DNS mapping, and Gatus uptime monitor. Schema-validated at evaluation time. Adding a service is one declaration in its own module — no edits scattered across `caddy.nix` + `blocky.nix` + `gatus.nix`.

```nix
nori.lanRoutes.<name> = {
  port = 8080;                      # required, types.port
  scheme = "http";                  # default
  exposeOnTailnet = false;          # default; opt in for direct backend access
  monitor = {                       # null = skip monitoring; { } = defaults
    path = "/health";               # default "/"
    interval = "60s";
    failureThreshold = 3;
  };
};
```

See `docs/CONVENTIONS.md` for the canonical service-module shape and how to extend lan-route (firewall opening + Authelia OIDC client auto-gen are the natural next extensions).

#### TLS + naming

Caddy terminates TLS for every `<name>.nori.lan` using its internal CA (auto-generated). The root cert is committed at `modules/server/caddy-local-ca.crt` and added to system trust via `security.pki.certificateFiles` so curl/Go/openssl trust it transparently. Python services need explicit `SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt"` (certifi doesn't read system trust).

Naming convention: function over brand. `chat.nori.lan` not `open-webui.nori.lan`. `auth.nori.lan` because "auth" *is* the function.

Devices accessing the homelab need to install the Caddy root CA once:
- Mac: `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain modules/server/caddy-local-ca.crt`
- Firefox/Zen: import via Settings → Privacy → Certificates (browsers don't read macOS keychain)
- iOS: AirDrop the cert, install via Settings → Profile, enable in Cert Trust Settings

#### Single Sign-On (SSO)

`Authelia` provides OIDC. Services that opt in get a one-click login flow (visit service → redirect to `auth.nori.lan` → log in once → returned authenticated). Per-service setup is auto-generated from the `nori.lanRoutes.<n>.oidc` block in each service module: lan-route generates the Authelia client entry, two sops secrets (raw + PBKDF2 hash), and a sops env-file template. Authelia's `template` config-filter reads the hash from sops at startup, so zero hash material lives in committed Nix. See `docs/CONVENTIONS.md` "Authelia OIDC pattern" for the bootstrap flow and `flake.nix`'s `forbidden-patterns` check for the enforcement.

#### DNS architecture

**Current state:** Blocky on both hosts — `nori-pi` in forwarder mode (primary, served to all tailnet devices via Tailscale's global-nameserver push pointing at Pi's tailnet IP) and `nori-station` in self-hosted mode (auto-generates the `*.nori.lan` map from `nori.lanRoutes`; serves as fallback secondary). LAN-only devices (smart TV, guest phones) are NOT covered — they keep using whatever the router pushes.

Blocky chosen over AdGuard Home for declarative-config friendliness — its YAML config maps cleanly to `services.blocky.settings`, no web-UI state to drift from declared config.

**Why Tailscale push instead of router DHCP:** the ISP-shipped Genexis EG400 (firmware `EG400-X-GNXRR-4.3.5.80-R-210105_1023`) locks DHCP DNS settings out of the user-facing admin UI. Router-side DNS replacement would require either (a) Altibox bridge-mode activation by phone request + a second router we control, or (b) double-NAT with a downstream router. Neither is set up; Tailscale push is the zero-hardware-cost workaround.

**Future state:** same as original DESIGN intent — Pi primary + nori-station secondary, both via router DHCP — but only after one of:
- Bridge-mode activation on the Genexis (then Pi's own DHCP server hands out itself + nori-station as DNS), or
- A separate router we control between LAN and ISP gateway

**Bootstrap loop hazard:** because nori-station's `/etc/resolv.conf` points at Tailscale's stub (`100.100.100.100`) and Tailscale forwards back to nori-station's Blocky, Blocky can't resolve its own outbound URLs (blocklist sources, DoH endpoints) before it's serving DNS. `services.blocky.settings.bootstrapDns` MUST be set to direct upstream IPs for this reason. Without it, blocklist downloads silently fail on every restart.

Both Blocky instances (current and future Pi) forward to a public resolver (1.1.1.1 or Quad9) for non-blocked queries. Tailnet hostnames resolved via Tailscale MagicDNS independently of Blocky.

#### Tailscale

`nori-pi` advertises:
- Subnet route for the home LAN (`--advertise-routes=192.168.1.0/24`)
- Exit node (`--advertise-exit-node`), opt-in per device

Both require approval in the Tailscale admin console (one-time).

`nori-station` runs Tailscale as a regular node, not a router. MagicDNS gives both hosts stable hostnames on the tailnet.

### Layer 5: Services

Native NixOS modules from day one. Verified module availability on `nixos-unstable` (current 26.05-pre):

| Service | Module | Host | Exposure |
|---|---|---|---|
| Jellyfin | `services.jellyfin` | nori-station | Tailnet |
| Ollama | `services.ollama` (CUDA) | nori-station | Tailnet |
| Open WebUI | `services.open-webui` | nori-station | Tailnet |
| Immich | `services.immich` (with VectorChord, Postgres 17) | nori-station | Tailnet |
| Samba | `services.samba` | nori-station | Tailnet, scoped to `/mnt/media`, `/srv/share` |
| Blocky (forwarder) | `services.blocky` (`nori.blocky.role = "forwarder"`) | nori-pi | LAN (via tailnet DNS push) |
| Blocky (self-hosted) | `services.blocky` (`nori.blocky.role = "self-hosted"`) | nori-station | LAN |
| Tailscale | `services.tailscale` | both | N/A |
| restic backup jobs | `services.restic.backups.<n>` | nori-station | N/A (outbound to Pi + Hetzner) |
| btrbk | `services.btrbk.instances.<n>` | nori-station | N/A (local) |
| ntfy server | `services.ntfy-sh` | nori-pi (appliance role; survives station outages — `alert.nori.lan` reverse-proxied cross-host) | Tailnet |
| ntfy `notify@` template | systemd unit | both hosts (each host's units POST to `ntfy.sh` directly, hostname-aware via `config.networking.hostName`) | N/A (outbound) |
| Gatus | `services.gatus` | both hosts (mutual probes — Pi watches station, station watches Pi, alerts via `ntfy.sh` independently) | Tailnet |
| Caddy | `services.caddy` | nori-station | Tailnet (HTTPS terminator + reverse proxy) |
| Authelia | `services.authelia.instances.<name>` | nori-station | Tailnet (OIDC issuer for SSO) |
| beszel hub | `services.beszel.hub` | nori-pi (forensics use case: when station hangs, hub keeps recording its metrics up to the last poll) | Tailnet (`metrics.nori.lan` reverse-proxied cross-host) |
| beszel agent | `services.beszel.agent` | both hosts (per-host telemetry; hub on Pi pulls over tailnet) | Tailnet |
| Sonarr | `services.sonarr` | nori-station | Tailnet (`tv.nori.lan`) |
| Radarr | `services.radarr` | nori-station | Tailnet (`movies.nori.lan`) |
| Prowlarr | `services.prowlarr` | nori-station | Tailnet (`indexers.nori.lan`) |
| Bazarr | `services.bazarr` | nori-station | Tailnet (`subtitles.nori.lan`) |
| Jellyseerr | `services.jellyseerr` | nori-station | Tailnet (`requests.nori.lan`) |
| qBittorrent | `services.qbittorrent` | nori-station | Tailnet (`downloads.nori.lan`); webuiPort=8083 (default 8080 collides with Open WebUI) |
| Lidarr | `services.lidarr` | nori-station | Tailnet (`music.nori.lan`); music *arr; library on @streaming |
| calibre-web | `services.calibre-web` | nori-station | Tailnet (`books.nori.lan`); ebook web UI + OPDS; library on @library; port 8084 (default 8083 collides with qBittorrent) |
| Komga | `services.komga` | nori-station | Tailnet (`comics.nori.lan`); comics/manga server + OPDS; library on @library; port 8085 (default 8080 collides with Open WebUI) |
| Glance | `services.glance` | nori-station | Tailnet (`home.nori.lan`); family-facing dashboard with service-status monitor + bookmarks + reading; port 8086 (default 8080 collides with Open WebUI) |
| Radicale | `services.radicale` | nori-station | Tailnet (`calendar.nori.lan`); CalDAV + CardDAV; htpasswd auth |
| Syncthing | `services.syncthing` | nori-station + future hosts | Tailnet (`sync.nori.lan` for the WebUI; peer port 22000 open on tailscale0) |
| Thunar | `programs.thunar` | nori-station | Local desktop only; lightweight GUI file manager + xdg-mime default |
| postgresqlBackup | `services.postgresqlBackup` | nori-station (if non-Immich PG) | N/A |

**Note on Immich's Postgres:** `services.immich.database.enable = true` (the default) provisions a Postgres instance owned by Immich, separate from `services.postgresql`. NixOS 25.11+ uses VectorChord (replacing pgvecto-rs) and Postgres 17 by default. Immich's own database management writes periodic dumps to `/var/lib/immich/backups/`. The backup pattern below picks up those dumps rather than running an external `pg_dump`.

#### Backup-correctness pattern (named)

Three flavors depending on service type. All use `services.restic.backups.<n>` from the NixOS module; the differences are in *what they back up* and *what runs before the backup*.

**Pattern A: Filesystem-only (no database).** Used for Jellyfin's library directory, Samba shares, `/home`, `/srv/share`. Just point restic at the path; filesystem snapshot is sufficient because the data isn't a database.

```nix
services.restic.backups.home = {
  paths = [ "/home" "/srv/share" ];
  repository = "sftp:nori-pi:/mnt/backup/home";
  passwordFile = config.sops.secrets.restic-password.path;
  timerConfig.OnCalendar = "daily";
  pruneOpts = [ "--keep-daily 14" "--keep-weekly 4" "--keep-monthly 12" ];
};
```

**Pattern B: Service with built-in dump (Immich).** Immich writes its own Postgres dumps to `/var/lib/immich/backups/` periodically. Backup picks up the dump directory, not the live database files. The directory is included in `/var/lib`; restic of `/var/lib/immich` plus the upload directories is sufficient *if and only if* Immich's internal backup is enabled and the timer beat the restic timer.

```nix
services.restic.backups.immich = {
  paths = [
    "/var/lib/immich/backups"     # SQL dumps (consistent point-in-time)
    "/var/lib/immich/upload"       # User uploads
    "/var/lib/immich/library"      # Imported library
    "/var/lib/immich/profile"      # User profiles
  ];
  repository = "sftp:nori-pi:/mnt/backup/immich";
  passwordFile = config.sops.secrets.restic-password.path;
  timerConfig.OnCalendar = "*-*-* 04:00:00";  # After Immich's nightly dump
  pruneOpts = [ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6" ];
};
```

**Pattern C: External dump before restic (services with their own external Postgres or SQLite).** Used when a service writes directly to a database without an internal dump mechanism. Two sub-flavors:

*C1 — `services.postgresqlBackup` for system-level Postgres:*
```nix
services.postgresqlBackup = {
  enable = true;
  databases = [ "openwebui" ];  # if applicable
  startAt = "*-*-* 03:30:00";
  pgdumpOptions = "--no-owner";
  location = "/var/backup/postgresql";
};
# Then restic backs up /var/backup/postgresql alongside other paths.
```

*C2 — `backupPrepareCommand` on the restic job for SQLite (used by some services):*
```nix
services.restic.backups.openwebui = {
  paths = [
    "/var/lib/open-webui"
    "/var/backup/open-webui"  # where the dump lands
  ];
  repository = "sftp:nori-pi:/mnt/backup/openwebui";
  passwordFile = config.sops.secrets.restic-password.path;
  backupPrepareCommand = ''
    mkdir -p /var/backup/open-webui
    ${pkgs.sqlite}/bin/sqlite3 /var/lib/open-webui/webui.db \
      ".backup '/var/backup/open-webui/webui.db'"
  '';
  timerConfig.OnCalendar = "daily";
};
```

The `backupPrepareCommand` runs as an `ExecStartPre` on the generated `restic-backups-<name>.service` unit. SQLite's `.backup` API produces a consistent snapshot even on a live database; raw `cp` does not.

**Pattern selection cheat sheet:**

| Service | Pattern | Rationale |
|---|---|---|
| Jellyfin | A | Library DB is SQLite but rebuilds from media; non-critical |
| Immich | B | Built-in dump mechanism |
| Open WebUI | C2 | SQLite, no internal dump |
| Ollama | A | Models are re-downloadable; chat history if any goes via Open WebUI |
| Cloudflared | A | Just credentials in `/var/lib/cloudflared` |
| Tailscale | A | State files |
| `/home`, `/srv/share` | A | No databases |

New services pick a pattern at onboarding time. (The patterns A/B/C live above; an earlier plan to split them into `docs/backup-patterns.md` was abandoned to avoid the indirection.)

#### Backup destinations

Two restic repositories per service, three retention policies:

| Service / Path | Pi (local fast restore) | Hetzner (off-site disaster) |
|---|---|---|
| `/home` | Daily, keep 14d + 4w | Weekly, keep 4w + 12m |
| `/srv/share` | Daily, keep 14d + 4w | Weekly, keep 4w + 12m |
| Immich (incl. dumps + uploads) | Daily, keep 7d + 4w | Daily, keep 7d + 4w + 12m |
| Open WebUI dump | Daily, keep 7d + 4w | Weekly, keep 4w + 12m |
| Other service state | Daily, keep 7d | Not backed up; re-derivable |
| Streaming media | Not backed up | Not backed up |
| `@photos`, `@home-videos`, `@projects` | Daily, keep 14d + 4w | Daily, keep 4w + 12m + yearly indefinite |

### Layer 6: Desktop environment

Hyprland on Wayland, on `nori-station` only, configured via home-manager as a NixOS module. Built end-to-end in Phase 6 — single Samsung S34J552 (3440x1440 @ 75Hz) on DP-3, Norwegian keymap mirroring `console.keyMap`, bibata cursor at 24px.

**Stack:**
- `greetd` + `tuigreet` — TTY → tuigreet → Hyprland. Requires `systemd.defaultUnit = "graphical.target"` to auto-start at boot (greetd's unit is `WantedBy=graphical.target`); without the bump, the boot path stops at `multi-user.target` and getty grabs tty1.
- `programs.hyprland` + `xdg-desktop-portal-{hyprland,gtk}` — system-side Hyprland; per-user keybinds in `modules/desktop/home.nix`.
- `pipewire` + `wireplumber` — audio. ALC892 onboard analog pinned as default sink via wireplumber rule (the codec match survives PCI renumbering and USB-device shuffling that would otherwise let the mic's monitor sink steal default).
- `waybar` (status bar), `mako` (notifications), `hyprlock` + `hypridle` (lockscreen + idle daemon, 10 min lock + 15 min DPMS off).
- Apps: `ghostty` (cross-machine consistency with laptop), `fuzzel` (launcher + cheatsheet renderer), `zen-browser` (community flake), `pwvucontrol`.
- Bind layer: keybinds + cheatsheet derived from one record list in `home.nix`. SUPER+H opens a fuzzel `--dmenu` cheatsheet; SUPER+L locks via logind.

**NVIDIA Wayland caveats** (worth knowing, not blockers):
- Multi-monitor with mixed refresh rates — VRR sometimes inconsistent (single-monitor today, untested).
- Suspend/resume edge cases on Blackwell-open — desktop is always-on so not currently exercised.
- Some Electron apps still need explicit `--ozone-platform=wayland` flags despite Electron 35+ syncobj support; `NIXOS_OZONE_WL=1` covers most via the NixOS-specific shim.

Driver 595 + explicit-sync removed most of the historical NVIDIA-Wayland pain. The session env-var set in `modules/desktop/hyprland.nix` is intentionally minimal (`NIXOS_OZONE_WL`, `__GLX_VENDOR_LIBRARY_NAME`); expand only when something concretely breaks.

### Layer 7: Operations

#### Repository structure

```
flake.nix
flake.lock                       # Pinned unstable revision; source of reproducibility
hosts/
  nori-station/
    configuration.nix
    disko.nix                    # Applied during Phase 4
    disko-media.nix              # Applied during Phase 2 (post-install)
    hardware.nix
  nori-pi/
    configuration.nix
    disko.nix                    # Applied during Phase 4
    hardware.nix
modules/
  common/                        # universal — every host imports this
    base.nix
    users.nix
    sops.nix
    tailscale.nix
    default.nix                  # also imports lib/* so options are available everywhere
  desktop/                       # graphical session — Hyprland, greetd, …
    hyprland.nix
    ...
  server/                        # this host serves things — server concern
    default.nix                  # imports every server module below
    authelia.nix
    blocky.nix
    caddy.nix
    caddy-local-ca.crt
    immich.nix
    jellyfin.nix
    ...                          # ~17 loose service files
    arr/                         # tightly-coupled *arr stack
      default.nix
      shared.nix
      sonarr.nix
      ...
    backup/                      # tightly-coupled durability stack
      default.nix
      restic.nix                 # Pattern A/B/C implementations
      verify.nix                 # quarterly restore drill
      btrbk.nix
  lib/
    lan-route.nix                # nori.lanRoutes option schema
    backup.nix                   # nori.backups option schema
secrets/
  secrets.yaml
  .sops.yaml
docs/
  DESIGN.md                      # this doc
  CONVENTIONS.md                 # repo patterns + enforcement layers
  gotchas.md                     # landmines from lived experience
  baremetal-install.md           # Phase 4 step-by-step
  vm-install.md                  # UTM dry-run target
  capacity-baseline.md           # Schema; values filled at quarterly reviews
  runbooks/
    bad-config.md
    file-deletion.md
    service-corruption.md
    drive-failure-root.md
    drive-failure-media.md
    pi-failure.md
    inspect-windows-drive.md     # MP510 read-only mount + verification
```

#### Disko at install

Disk layouts in `hosts/<host>/disko.nix` from day zero. First install path:

1. Boot NixOS minimal installer USB
2. SSH into installer (set `sshd` enabled in installer config) or work locally
3. Clone the flake: `git clone https://github.com/phibkro/homelab /tmp/homelab`
4. Run disko: `nix --experimental-features 'nix-command flakes' run github:nix-community/disko/latest -- --mode disko /tmp/homelab/hosts/nori-station/disko.nix`
5. `nixos-install --flake /tmp/homelab#nori-station`
6. Reboot, set user password on first login, push generated flake.lock back to Git

This is the explicit path. **`nixos-anywhere` is the alternative** for fully-remote installs (SSH'd into the installer from the laptop), but the path above is the one to execute first since you'll be at the machine anyway.

#### Distributed builds, not cross-compilation

Pi builds are slow on aarch64 hardware. The optimization is **distributed build to a remote builder**: build on `nori-station` (x86_64 with aarch64-binfmt + qemu-user), copy the closure to `nori-pi`, activate. `nh` and `nixos-rebuild --build-host` handle this transparently.

This is *not* cross-compilation (which means x86_64 producing aarch64 binaries directly). Cross-compilation in nixpkgs is rougher than people expect for full system closures. binfmt-emulated native build on a fast x86 host is the pragmatic answer.

```nix
# On nori-station, enable aarch64 emulation
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
```

```bash
# On laptop, deploy to Pi using nori-station as builder
nh os switch --target-host nori-pi --build-host nori-station .#nori-pi
```

#### Deploy loop

Edit on laptop → `nh os switch --target-host <host>` → atomic activation → commit on success, revert via NixOS generations on failure.

`deploy-rs` remains a future option if "deployed broken config, lost remote access" ever happens. Not adopted initially.

#### Secrets

`sops-nix` with `age` keys derived from SSH host keys via `ssh-to-age`. Introduced when the first secret is needed (likely with restic-password for Phase 4-5).

---

## Data and backup model

### Three value tiers

| Tier | Examples | Snapshot | Local backup (Pi) | Off-site (Hetzner) |
|---|---|---|---|---|
| Re-derivable | Streaming media, Ollama models, Nix store, package caches | Weekly or none | No | No |
| Service state | Jellyfin DB, Immich DB+uploads, Open WebUI, Cloudflared creds | Daily | Yes | Selected (Immich uploads yes; Open WebUI yes; Cloudflared no — re-create) |
| Irreplaceable | Personal photos, home videos, finished projects, work in progress, flake repo | Hourly to daily | Yes | Yes |

System config covered by Git mirrored to GitHub; not a backup target.

### Hetzner Storage Box sizing

Pricing (April 2026): BX11 (1TB) ~3.20 EUR/mo, BX21 (5TB) ~10.80 EUR/mo, BX31 (10TB) ~20.80 EUR/mo. Plans scale up/down without data migration; cancellation any time.

**Initial sizing:** start at BX11 (1TB) if irreplaceable data is currently <500GB. Re-evaluate when home-videos archive grows past 700GB. **This belongs in `docs/capacity-baseline.md` and is reviewed quarterly.**

### Backup verification

- **Weekly:** `restic check` (metadata only).
- **Monthly:** `restic check --read-data-subset=10%` (rolling sample, full repository covered every ~10 months).
- **Quarterly:** restore drill — restore one subvolume's recent snapshot to `/var/restore-test/`, diff against live, document time.

Failure of any of these alerts via ntfy.

---

## Access and exposure model

| Path | SSH (user) | SSH (root) | Samba | Cloudflare Tunnel | Snapshot |
|---|---|---|---|---|---|
| `/home/philip` | Yes | Yes | No | No | Hourly |
| `/srv/share` | Yes | Yes | Yes (auth) | No | Daily |
| `/mnt/media/streaming` | Yes | Yes | Yes (auth, RW) | Via Jellyfin only | Weekly |
| `/mnt/media/photos` | Yes | Yes | No | Via Immich only | Daily |
| `/mnt/media/home-videos` | Yes | Yes | No | Via Immich only | Weekly |
| `/mnt/media/projects` | Yes | Yes | Yes (auth) | No | Weekly |
| `/var/lib/<service>` | No | Yes | No | Service's own protocol | Daily |
| `/etc`, `/nix`, `/root` | No | Yes | No | No | Per system rebuild (`@`) |

OS has one user (Philip). Family members get per-service accounts in Jellyfin, Immich, Open WebUI; their devices get Tailscale invites.

---

## Observability and alerting

**beszel** for metrics (hub on nori-station, agents on both hosts, accessed over Tailscale).

**Gatus** for synthetic HTTP/TCP/DNS checks. Replaced an earlier Uptime Kuma plan after recognising that Uptime Kuma's web-UI-driven config didn't fit a code-as-config repo. Gatus is pure declarative — endpoints, conditions, alert routing all live in the Nix attrset that renders to gatus's YAML.

**ntfy** for alert delivery (self-hosted on nori-station, Tailscale-only). High-priority topic for urgent (sound, bypass DND); normal priority for warnings.

### Monitored conditions

| Condition | Source | Severity |
|---|---|---|
| Filesystem >80% full | beszel | Warn |
| Filesystem >90% full | beszel | Urgent |
| SMART status changes | systemd timer | Urgent |
| Service down (HTTP / TCP probe) | Gatus | Urgent |
| Tailscale connectivity loss | systemd timer | Urgent |
| restic backup job failure | restic systemd unit | Urgent |
| btrbk snapshot job failure | btrbk systemd unit | Warn |
| Sustained high CPU/memory | beszel | Warn |

### Alert delivery

| Type | Channel | Trigger |
|---|---|---|
| Real-time, low priority | ntfy default topic | Warnings |
| Real-time, high priority | ntfy urgent topic | Service down, drive failing, backup failed |
| Routine summary | Email digest, weekly | All metrics summarized; deferred to "future task" |

Email digest deferred. When set up: SMTP via Gmail with app password (sufficient for machine-generated reports; Proton Bridge's complexity not warranted for non-private content).

---

## Phasing (canonical)

| Phase | Description | State |
|---|---|---|
| 0 | Inventory + flake skeleton | done |
| 1 | Backups (rsync + partclone) | done; verified on One Touch |
| 2 | Reformat IronWolf Pro to btrfs | done (pulled forward into Phase 5; see "Repository conventions") |
| 3 | VM dry-run install (UTM) | done; `vm-test` on tailnet |
| 4 | Bare-metal install on nori-station | done |
| 5 | Service migration | in progress (file/AI/media/SSO/observability live: Samba, Blocky, Ollama, Open WebUI, Jellyfin, sops, restic Pattern A+C2, Caddy, Authelia, Gatus, beszel hub, ntfy. Pending: Immich, Cloudflare Tunnel, Hetzner off-site restic) |
| 6 | Desktop environment | done — Hyprland + greetd + waybar + mako + hyprlock + hypridle on nori-station |
| 7 | `hosts/nori-pi/` live + cross-host service split | done — Pi appliance bringup, mutual observability, Beszel hub + ntfy server migrated to Pi via the cross-host split-module pattern (CLAUDE.md "How to relocate a service to nori-pi") |

**Reactive phases (no scheduled trigger):**

- **Cloudflare Tunnel + Cloudflare Access.** When Tailscale friction emerges (someone refuses to install another app, public link sharing needed).
- **Email digest reports.** When ntfy alone proves noisy enough that summarization helps.
- **Second media drive on nori-station.** When IronWolf >80% full or RAID1 redundancy becomes desired.
- **deploy-rs.** When a "deployed broken config, lost remote access" incident occurs.
- **disko adoption refactor.** Already adopted at install; this is a no-op.

---

## Open items

Captured for visibility, not currently being worked:

- **UPS for nori-station.** Single PSU is a non-goal for HA, but mid-write power loss on USB-attached IronWolf is a real recovery scenario. Cheap (~1500-3000 NOK for 600VA) insurance. No commitment yet.
- **Migration of IronWolf Pro from USB to internal SATA.** When SATA capacity becomes available (e.g., adding a SATA HBA via PCIe). USB enclosures have their own failure mode at the controller level.
- **`common-cpu-amd-pstate`** module on nori-station hardware. Deferred from Phase 3.
- **Authelia/Authentik self-hosted SSO.** Triggered by Cloudflare Access becoming insufficient.
- **NVIDIA Wayland edge cases** (multi-monitor VRR, suspend/resume nuances). Not blocking; document fixes in `hardware.nix` as they're encountered.
- **CUDA/Ollama drift.** Stable 25.11 had a CUDA 13 / 12.8 toolkit mismatch breaking some CUDA apps. Ollama bundles its own CUDA libs typically; verify Ollama works at install and pin nixpkgs version if it doesn't.
- **Home automation on the Pi.** Not currently planned; no concrete use case.

---

## Permanent constraints (non-negotiable)

- **Never touch the Windows drive** (Corsair Force MP510, by-id `nvme-Force_MP510_2031826300012953207B`). Disambiguate by **model string and by-id**, never by `/dev/nvmeN`. NVMe enumeration is unstable across reboots — at install time the WD Black SN750 (NixOS) was `nvme0n1` and the MP510 (Windows) was `nvme1n1`; post-reboot they swapped. A re-run of disko targeting the wrong `/dev` path would wipe Windows. (Caught this latently after the swap; fixed by switching all disko configs to `/dev/disk/by-id/...`.)
- **Disko configs MUST target `/dev/disk/by-id/...` paths**, not `/dev/nvmeN` or `/dev/sdX`. by-id paths follow the hardware; `/dev` paths follow PCIe scan order.
- **Don't schedule destructive system changes during weeks with Aker demo pressure.**
- **Backup verification is part of the system, not optional.** Quarterly restore drill is the real RTO measurement.
- **Phase 2 (IronWolf reformat) does not happen during Phase 4 (install).** Two separate, sequential operations. Do not combine. (Phase 2 was eventually pulled forward as part of Phase 5 service migration, *after* Phase 4 was complete — same constraint, different timing than original plan.)

---

## Design rationales (load-bearing decisions)

**Unstable channel, not stable.** Blackwell support requires NVIDIA driver 575+; stable 25.11 lags. flake.lock pins the unstable revision, providing reproducibility within the rolling channel. Re-pin deliberately, not on every flake update.

**Btrfs everywhere instead of ext4 root.** Consistency of mental model; `@home` snapshots useful; `@var-lib` snapshots provide service-recovery beyond NixOS generations. CoW gotcha for databases addressed via `chattr +C` or `nodatacow`, separately from backup-consistency (logical dumps).

**No ZFS.** Single-drive scale doesn't activate ZFS's main wins. Out-of-tree driver constrains kernel versions, conflicts with bleeding-edge Blackwell driver needs.

**Default-deny exposure with explicit per-interface firewall.** Default-allow with exclusions is a maintenance treadmill that grows with every new file or service.

**Default-deny filesystem access for service modules.** The same principle as above, applied to systemd's mount namespace. Every service runs with `TemporaryFileSystem` over `/mnt` and `/srv` (replacing them with empty tmpfs at service-namespace level), `ProtectHome=true` (hiding `/home` and `/root`), and an explicit allowlist of host paths bound back in. Default no access; opt in per path. A compromised service can't browse the host looking for credentials, even if it can exec shell commands.

The principle is enforced in code via `nori.harden.<unit>` (`modules/lib/harden.nix`) plus the `every-service-has-fs-hardening` flake check that fails the build if any service module forgets to declare it:

```nix
nori.harden.<service> = {
  binds         = [ /* writable host paths */ ];
  readOnlyBinds = [ /* /mnt/media, /srv/share, etc. only if needed */ ];
};
```

Verify via `sudo systemctl cat <unit>.service | grep -E '(ProtectHome|TemporaryFileSystem|Bind)'` for the configured form, or `sudo nsenter -t <pid> -m -U -- ls /mnt/` for the live namespace. Several upstream NixOS modules already harden some surfaces (`ProcSubset=pid`, `ProtectKernelTunables`, etc.) but leave the mount namespace wide open by default; that's the gap this principle plugs.

**Hyprland over GNOME/KDE.** Declarative config matches the rest of the system. Tiling matches keyboard-heavy terminal use.

**Subvolumes split by value tier, not by directory hierarchy.** Subvolumes are the unit of snapshot/backup policy. Same policy → same subvolume; different policy → different subvolume.

**Disko at install, not deferred.** First install is the right time. Deferring guarantees doing the work twice.

**Pi as appliance + opportunistic backup target.** The marginal cost of a USB HDD on the Pi is low; the value (fast local restore) is high. Failure modes remain independent of nori-station.

**Two adblock-aware DNS resolvers (Pi + nori-station), not Pi-only-with-router-fallback.** DHCP-distributed secondaries don't fail over fast; resolver timeouts mean Pi-down = seconds of broken DNS. Running Blocky on both hosts makes Pi outages transparent at trivial resource cost. Both live today — Pi runs forwarder mode (delegates `*.nori.lan` to station), station runs self-hosted mode (auto-generates the `*.nori.lan` map from `nori.lanRoutes`). Tailscale's global-nameserver push points at Pi as primary; if Pi goes down, tailnet devices fall back to the secondary instance via the admin-console-configured nameserver list.

**Blocky over AdGuard Home.** Declarative YAML config maps cleanly to NixOS module options; no web-UI state to drift from declared config.

**restic over btrbk send/receive for backup transport.** Filesystem-agnostic (Pi backup drive doesn't need to be btrfs). Same tool for Pi target and Hetzner target — single mental model.

**Cloudflare Access over self-hosted SSO (Authelia/Authentik).** At household scale, free, requires no self-hosted infrastructure.

**Backup-correctness via three documented patterns (A/B/C), not assumption.** Filesystem snapshot of a live database is roulette. Logical dumps before backup is the discipline; the patterns document which kind of dump for which kind of service.

---

## Recovery runbooks

In `docs/runbooks/`. Initial outlines:

- **`bad-config.md`:** NixOS rollback (boot menu or `nixos-rebuild --rollback switch`).
- **`file-deletion.md`:** identify subvolume, find pre-deletion snapshot in `/.snapshots`, copy out.
- **`service-corruption.md`:** stop service, restore subvolume snapshot to scratch path, copy back, restart, verify. For databases: restore from latest restic snapshot of the dump directory, then `pg_restore` or SQLite import.
- **`drive-failure-root.md`:** replace drive → boot installer → clone flake → run disko → `nixos-install` → restic restore service state from Pi (faster) or Hetzner (slower).
- **`drive-failure-media.md`:** replace drive → mkfs.btrfs + subvolumes → restic restore irreplaceable subvolumes from Pi → re-download streaming media from sources.
- **`pi-failure.md`:** swap to spare USB SSD with current flake → boot → verify Blocky and Tailscale come up → router DHCP unaffected (nori-station is secondary DNS).

---

## Capacity baseline

Recorded in `docs/capacity-baseline.md` at Phase 4 completion. Values to capture:

- Free space per subvolume on nori-station and nori-pi
- Used space per subvolume on IronWolf (post-Phase-2)
- RAM at idle (no Ollama loaded)
- RAM with one Ollama model loaded (32B Q4 baseline)
- Average sustained CPU during evening peak (after Phase 5)
- Hetzner Storage Box usage

Re-checked quarterly. Growth trends inform when a second drive on nori-station is warranted, when Hetzner tier needs upgrading, when Ollama model size needs to come down.

---

## Repository conventions

- `nh` for daily rebuilds. `nixos-rebuild` directly for edge cases.
- `nixfmt-rfc-style` formatting; `statix` linting; `deadnix` for unused bindings. Pre-commit hooks.
- `nixd` LSP for editor integration. `direnv` + `nix-direnv` for dev shells.
- Commit messages: imperative mood. Conventional commits not enforced.
- `main` is what's deployed. Feature branches for non-trivial changes. Squash-merge.

---

## Closing

This is the canonical design. The flake repo is the source of truth for implementation; this doc is the source of truth for *why*. When implementation drifts from design, the design is updated to match (or implementation is reverted). Reality and documentation in sync, by convention.

Phase 4 ready when you're at nori-station with a USB.
