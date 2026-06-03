---
summary: Repository structure, service module template, FS hardening (`nori.harden`),
  sops patterns, packages-by-scope, dev shells, commit + code style. The "how the
  code is shaped" reference. Rules ABOUT modules live in ENFORCEMENT.md.
---

# Modules

Repository-wide patterns for *writing* modules. Rules and how they're checked live in `ENFORCEMENT.md`; this file is the shape of the code itself.

## Repository structure

```
flake.nix
flake.lock                       # Pinned 26.05 revision; source of reproducibility
machines/
  core.nix                       # Shared interactive-user home-manager baseline
  workstation/
    default.nix                  # NixOS host config
    hardware.nix
    disko.nix                    # Applied at install
    disko-media.nix              # Applied post-install (IronWolf reformat)
    home.nix                     # Pure home-manager module
    hyprland.lua                 # Lua config for Hyprland 0.55+
  pi/
    default.nix
    hardware.nix
    disko.nix
    home.nix
  macbook/
    home.nix                     # Standalone home-manager (no NixOS layer)
modules/
  common/                        # Universal infra — every host imports
    default.nix
    base.nix · users.nix · sops.nix · tailscale.nix
  effects/                       # Cross-cutting `nori.<X>` declarative options
    hosts.nix · gpu.nix · fs.nix          # Reader-shaped
    lan-route.nix · backup.nix · harden.nix  # Writer-shaped
  server/                        # "This host serves things"
    default.nix                  # workhorse bundle (station imports whole; pi picks flat)
    <service>.nix                # Loose: independent services
    arr/                         # Tightly-coupled *arr stack
    backup/                      # Tightly-coupled durability stack
    beszel/                      # Cross-host hub + agent split
    ntfy/                        # Cross-host server + notify split
  desktop/                       # "This host has a graphical session"
    hyprland.nix · greetd.nix · stylix.nix · apps.nix
  dev/                           # Dev-shell fragments composed via mkDevShell
  claude-code/                   # Operator's global Claude config (skills + settings)
secrets/
  secrets.yaml · apps.yaml · .sops.yaml
docs/
  decisions/                     # ADRs — hard-to-reverse decisions, dated
  runbooks/                      # Per-failure step-by-step recovery
  superpowers/                   # Per-feature specs and plans
  <REFERENCE>.md                 # Tier-2 reference docs (see CLAUDE.md routing)
.claude/
  skills/                        # Procedure skills (load on demand)
```

## Configuration derivation from layout

The flake derives configurations from the directory structure:

| Detected | Produces |
|---|---|
| `./machines/<n>/default.nix` | `nixosConfigurations.<n>` (NixOS host) |
| `./machines/<n>/home.nix` without `default.nix` | `homeConfigurations.<n>` (e.g. Mac; activated via standalone home-manager) |
| NixOS hosts that have `home.nix` | Activate via `home-manager-as-NixOS-module` inside their own `default.nix` |

`machines/<n>/home.nix` is a **pure home-manager module** regardless of the host's OS. Same file shape across NixOS + standalone — no platform-specific module conventions inside `home.nix`.

`machines/core.nix` is the shared user-scope baseline imported by every machine's `home.nix` via `imports = [ ../core.nix ]`. Cross-platform CLI + identity (starship, programs.git, comma, sops/age/claude-code, just/ripgrep/tmux).

## Concerns compose host identity

`modules/<concern>/` directories represent host roles. A host's identity is the sum of which concerns it imports plus its hardware:

| Concern | What it adds | Imported by |
|---|---|---|
| `common/` | Universal infra: base, users, Tailscale, sops + the `effects/` interface options | every host |
| `server/` | *This host serves things*: Caddy, Authelia, *arr, backups, media, monitoring | workstation (whole bundle); pi (flat-picks specific files) |
| `desktop/` | *This host has a graphical session*: Hyprland, greetd, audio | workstation; future `nori-laptop` |
| `effects/` | Reader + Writer interface options | imported by `common/`; populated by hosts (Reader) and services (Writer) |

A typical NixOS host file:

```nix
# machines/workstation/default.nix
imports = [
  inputs.disko.nixosModules.disko
  ../../modules/common
  ../../modules/server
  ../../modules/desktop
  ./hardware.nix
  ./disko.nix
];
```

Reading this answers "what kind of machine is `workstation`?" at a glance. `pi` lives as `common +` *flat imports of specific server modules* (Blocky, Gatus, Beszel hub+agent, ntfy server+notify) — the bundle import is too coarse for the appliance role.

### Coupling vs categorization

**Within `modules/server/`, folders signal coupling, not categorization.** Tightly-coupled clusters get their own folder + `default.nix`:

| Cluster | Coupling |
|---|---|
| `arr/` | Sonarr/Radarr/Lidarr/Bazarr/Jellyseerr/Prowlarr/qBittorrent — reference each other via API; share `/mnt/media/streaming` via the `media` group + `arr/shared.nix` tmpfiles |
| `backup/` | `restic.nix` + `verify.nix` + `btrbk.nix` — share `/mnt/backup`, the `restic-password` sops secret, the `notify@` failure pipeline |
| `beszel/`, `ntfy/` | Cross-host split-module pattern |

Loose services that just happen to be in the same conceptual area (Beszel, Gatus, Glance, ntfy — all observability-shaped but mutually independent) stay flat at `server/`'s top level.

## Service module template

A service module owns *everything* about its service in one file. No fan-out.

```nix
{ config, lib, pkgs, ... }:
{
  # Upstream module
  services.<service> = {
    enable = true;
    # ...service-specific config...
  };

  # Default-deny FS namespace — attribute key MUST match the systemd service unit name
  nori.harden.<service> = {
    binds = [ /* writable host paths */ ];
    readOnlyBinds = [ /* read-only host paths */ ];
    # protectHome = null;  # rare: only when upstream's value is opinionated (e.g. syncthing)
  };

  # LAN exposure — auto-generates Caddy vhost + Blocky DNS + Gatus monitor
  nori.lanRoutes.<short-name> = {
    port = N;
    monitor = { };  # or .path = "/health" if non-default
  };

  # Backup intent (required — `every-service-has-backup-intent` flake check)
  nori.backups.<service>.paths = [ "/var/lib/<service>" ];
  # or for stateless / re-derivable services:
  # nori.backups.<service>.skip = "<reason>";

  # Optional: open backend port directly on tailnet (default: closed)
  # nori.lanRoutes.<short-name>.exposeOnTailnet = true;
}
```

## Filesystem hardening (`nori.harden`)

The default-deny systemd FS-namespace block (`ProtectHome = mkForce true`, `TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ]`, plus `BindPaths` / `BindReadOnlyPaths` for what's let back in) lives behind the `nori.harden` abstraction in `modules/effects/harden.nix`.

```nix
nori.harden.<unit> = {
  binds         = [ /* writable host paths */ ];
  readOnlyBinds = [ /* read-only host paths */ ];
  protectHome   = true | false | null;  # default true; null skips
};
```

The `every-service-has-fs-hardening` flake check fails the build if any `modules/server/*.nix` is missing a `nori.harden.<n>` declaration (excluded list: aggregators, framework, ntfy/notify, samba's legitimate /srv exception).

Verify a service's effective namespace:

```sh
sudo systemctl cat <unit>.service | grep -E '(ProtectHome|TemporaryFileSystem|BindPaths|BindReadOnlyPaths)'
sudo nsenter -t <pid> -m -U -- ls /mnt/    # confirm live namespace shows only bound paths
```

Common shapes:

| Shape | Declaration |
|---|---|
| No host access (the default) | `nori.harden.<n> = { };` |
| Writable subtree (e.g. *arr hardlink into /mnt/media/streaming) | `binds = [ "/mnt/media/streaming" ];` |
| Read-only subtree (e.g. Jellyfin streaming) | `readOnlyBinds = [ "/mnt/media" "/srv/share" ];` |
| Upstream-opinionated ProtectHome (Syncthing) | `protectHome = null;` |
| Extra serviceConfig (CPUQuota, EnvironmentFile, …) | Declare in a sibling `systemd.services.<n>.serviceConfig` block — module merging combines them |

## Shared-file access: the `media` group

Services that read/write the same files on `@downloads` / `@library` join a single shared `media` group. Each service runs as its own uid (`sonarr`, `radarr`, `qbittorrent`, `jellyfin`, `immich`, `komga`, `calibre-web`) but all are members of gid `media`. Library dirs are `root:media 02775` (setgid + group rwx), so new files inherit `media` automatically.

```nix
users.users.<svc>.extraGroups = [ "media" ];
```

This is what makes the qBittorrent → *arr hardlink-on-import flow work — distinct uids, shared gid, group-writable files (set via qBittorrent's `UMask=0002`). Without it the kernel's `fs.protected_hardlinks=1` makes `link()` fail with EPERM and *arr silently falls back to reflink/copy. See `.claude/skills/gotcha-arr-reflinks-not-hardlinks/`.

Canonical doc: `modules/server/arr/shared.nix` header comment.

## Secrets: sops-nix patterns

### Single-value secrets

```yaml
# secrets.yaml
restic-password: <random>
oidc-chat-client-secret: <random>
```

```nix
sops.secrets.restic-password = {
  mode = "0440";
  owner = "<service-user>";   # static user, or:
  group = "keys";              # for DynamicUser services
};

services.foo.passwordFile = config.sops.secrets.restic-password.path;
```

### Env-file format (for `EnvironmentFile=`)

Two key things: (1) the template content uses sops placeholder substitution at activation time; (2) the format is `KEY=VALUE` env-file syntax — **`=`, not `:`**, and YAML block-string in sops adds a trailing newline that env-file expects.

```yaml
# secrets.yaml
gatus-env: |
  NTFY_CHANNEL=nori-claude-jhiugyfthgcv
```

```nix
# Combining multiple sops secrets into one env file:
sops.templates."open-webui-oauth-env" = {
  mode = "0440";
  group = "keys";
  content = ''
    OAUTH_CLIENT_SECRET=${config.sops.placeholder.oidc-chat-client-secret}
  '';
};

systemd.services.open-webui.serviceConfig = {
  EnvironmentFile = config.sops.templates."open-webui-oauth-env".path;
  SupplementaryGroups = [ "keys" ];   # DynamicUser needs this for /run/secrets read
};
```

### DynamicUser caveats

NixOS services using `DynamicUser=yes` (open-webui, ollama, ntfy-sh, beszel-hub, gatus) get a fresh UID per session. Implications:

| Caveat | Workaround |
|---|---|
| Can't `chown <name>:<name>` — users don't exist statically | `chown --reference=<existing-file>` to copy ownership from a sibling |
| `/run/secrets/*` is `0440 root:keys` | `SupplementaryGroups = [ "keys" ]` to grant access |
| `StateDirectory` is `/var/lib/private/<name>` symlinked to `/var/lib/<name>` | Don't add the symlink path to backups directly — see `.claude/skills/gotcha-dynamicuser-statedirectory-symlink/` |

Adding a new OIDC client → `/add-oidc-client` (procedure skill — bootstrap, sops paste, route declaration, systemd wiring).

## Packages: where things live by scope

Packages and config live at one of four scopes. Pick the **lowest** scope that gets the tool to its actual audience — drift goes the other way (a tool only the operator uses ends up at system scope and has to be moved later).

| Scope | Where | Audience | Examples |
|---|---|---|---|
| **System floor** | `modules/common/base.nix` `environment.systemPackages` | Every host (incl. pi, which has no home-manager); root, sshd, system services | `bat curl dig fd git htop just ripgrep tmux tree vim wget` |
| **System desktop** | `modules/desktop/apps.nix` `environment.systemPackages` + `fonts.packages` | Workstation Linux desktop session — Hyprland-invoked apps, GUI clients, fonts | `ghostty fuzzel hyprpaper zen bitwarden-desktop zed-editor davinci-resolve nerd-fonts.jetbrains-mono` |
| **User core** | `machines/core.nix` `home.packages` + `programs.<x>` | Every interactive machine where nori is the operator | `comma starship programs.git age sops claude-code` |
| **Per-machine user** | `machines/<host>/home.nix` `home.packages` | One specific machine | workstation: `nvtop` (NVIDIA), `compsize` (btrfs), Hyprland binds; Mac: `bun pnpm ffmpeg`, `home.file."Library/Fonts/..."`, `NODE_EXTRA_CA_CERTS` |

Decision rules:

- Needed by root / system services / pi? → **system floor**
- Coupled to the Linux desktop session (Hyprland binds, fontconfig, GUI launchers)? → **system desktop**
- Interactive operator tool, every machine? → **user core**
- Machine-specific? → **per-machine user**

Acceptable cross-scope overlap: `git` lives in both `base.nix` (for root + Nix's flake operations) and `core.nix` `programs.git` (for the operator's per-user config). Both load-bearing.

What does NOT belong in `core.nix`: anything platform-specific (NVIDIA tools, Wayland-only programs, Linux fontconfig). Cross-platform CLI only — if the tool doesn't build on `x86_64-darwin`, it's not core.

## Dev shells (`mkDevShell` fragments)

`modules/dev/<n>.nix` are atomic dev-environment fragments — a language toolchain, runtime, package manager, tool, or service. The composer at `modules/dev/default.nix` exposes:

```nix
mkDevShell pkgs { modules = [ "ts" "nix" "claude-code" ]; }
```

The composer resolves transitive deps, dedupes `buildInputs`, merges Claude allowlists. The `claude-code` fragment is the **consent signal**: present → composer materializes `.claude/settings.json`; absent → contributions are collected silently (project usable without Claude Code).

Reachable from downstream project flakes via `self.lib.mkDevShell`. Live fragments: `nix eval .#lib.fragmentNames`.

## Dev workflow

`Justfile` at repo root for common workflows. Install: `pkgs.just` already in `modules/common/base.nix`; `brew install just` on macOS.

```sh
just                          # default: rebuild via rsync + nh os switch
just <recipe> [<host>]        # all recipes accept optional host arg
just status                   # failed units + disk + restic/btrbk timer summary
just logs <unit>              # last 50 journal lines
just check                    # nix flake check
just deploy                   # git push + nh os switch from origin (no rsync)
just rollback                 # previous generation
just backup <repo>            # immediately run restic-backups-<repo>
just snapshots <repo>         # list restic snapshots
just --list                   # all recipes
```

`nh os switch` is the rebuild engine — replaces `nixos-rebuild`. Internal sudo (don't prefix); shows ADDED/REMOVED/CHANGED diff before activating.

Default host is `workstation`; pass another to deploy elsewhere. SSH targets via Tailnet MagicDNS.

### Distributed builds, not cross-compilation

Pi builds are slow on aarch64. The optimization is **distributed build to a remote builder**: build on workstation (x86_64 with aarch64-binfmt + qemu-user), copy the closure to pi, activate. This is *not* cross-compilation — cross-compilation in nixpkgs is rougher than expected for full system closures.

```nix
# On workstation:
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
```

```sh
# Deploy to Pi using workstation as builder:
nh os switch --target-host pi --build-host workstation .#pi
```

### Disko at install

Disk layouts in `machines/<host>/disko*.nix` from day zero. First install:

1. Boot NixOS minimal installer USB
2. SSH into installer or work locally
3. Clone the flake to `/tmp/homelab`
4. `nix --experimental-features 'nix-command flakes' run github:nix-community/disko/latest -- --mode disko /tmp/homelab/machines/workstation/disko.nix`
5. `nixos-install --flake /tmp/homelab#workstation`
6. Reboot, set password on first login, push generated flake.lock

Detailed step-by-step in `docs/baremetal-install.md`. `nixos-anywhere` is the fully-remote alternative.

## Commit + code style

| Layer | Rule |
|---|---|
| Conventional Commits | `type(scope): summary` |
| Body | Explain *why* and what was tried |
| Co-authored attribution | `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` on agent-driven commits |
| Formatter | `nixfmt` (set as the flake formatter) |
| Linter | `statix` (anti-patterns) + `deadnix` (unused bindings) |
| Pre-commit | `.githooks/pre-commit` runs `nix flake check`; skips gracefully if nix isn't on PATH (Mac case); CI catches the skipped commits |
| Branching | Commit directly to `main`. Solo-with-agents; no feature branches (see ADR-0001) |
