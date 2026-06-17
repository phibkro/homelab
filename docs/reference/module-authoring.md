---
summary: Repository structure, service module template, FS hardening (`nori.harden`),
  sops patterns, packages-by-scope, dev shells, commit + code style. The "how the
  code is shaped" reference. Rules ABOUT modules live in docs/invariants.md.
---

# Module authoring

Repository-wide patterns for *writing* modules. Rules and how they're checked live in `docs/invariants.md`; this file is the shape of the code itself.

## Repository structure

```
flake.nix
flake.lock                       # Pinned 26.05 revision; source of reproducibility
machines/                        # PER-HOST: NixOS system config only
  workstation/    pi/    pavilion/    aurora/   # NixOS hosts (default.nix + hardware + disko + home.nix)
  macbook/                       # Standalone home-manager (no NixOS layer)
home/                            # HOME-MANAGER modules (user-space, dotfiles, CLIs)
  core.nix                       # cross-platform CLI baseline — every host imports
  pc.nix                         # operator-PC tier — heavy closures (claude-code, hermes)
  claude-code/                   # CLI + ~/.claude/skills/* + settings.json
  hermes/                        # Hermes Agent CLI (Linux-only; skips on Mac)
modules/                         # NixOS modules (root, system)
  common/                        # universal infra — every host imports
    base.nix · users.nix · sops.nix · tailscale.nix · vector.nix
  effects/                       # `nori.<X>` Reader + Writer interface options
    hosts.nix · gpu.nix · fs.nix              # Reader-shaped
    lan-route.nix · backup.nix · harden.nix   # Writer-shaped
    gatus-probe.nix · resource-tiers.nix · restart-policy.nix · rust-motd.nix · hosts.nix
  services/                      # "this host serves things"
    default.nix                  # workhorse bundle (workstation imports whole; pi picks flat)
    <service>.nix                # loose: independent services
    arr/    backup/    beszel/    ntfy/    victorialogs/   # tightly-coupled clusters
  desktop/                       # "this host has a graphical session"
    hyprland.nix · greetd.nix · stylix.nix · apps.nix · ...
  dev/                           # dev-shell fragments composed via mkDevShell
secrets/
  secrets.yaml · apps.yaml · .sops.yaml
docs/
  decisions/                     # ADRs — hard-to-reverse decisions, dated
  runbooks/                      # per-failure recovery
  superpowers/                   # per-feature specs + plans
  RUNTIME_TESTS.md               # runtime introspection framework + recipes
  <REFERENCE>.md                 # tier-2 reference docs (see CLAUDE.md routing)
.claude/
  skills/                        # procedure skills (load on demand)
```

**Layout principle:** `machines/<host>/` = pure machine-specific NixOS wiring; `home/` = home-manager (cross-host operator-side); `modules/infra/` = `nori.<X>` declarative options; `modules/services/` = NixOS-side service modules. The split between `modules/` and `home/` is the **NixOS-vs-home-manager** module-system boundary.

## Configuration derivation from layout

The flake derives configurations from the directory structure:

| Detected | Produces |
|---|---|
| `./machines/<n>/default.nix` | `nixosConfigurations.<n>` (NixOS host) |
| `./machines/<n>/home.nix` without `default.nix` | `homeConfigurations.<n>` (e.g. Mac; activated via standalone home-manager) |
| NixOS hosts that have `home.nix` | Activate via `home-manager-as-NixOS-module` inside their own `default.nix` |

`machines/<n>/home.nix` is a **pure home-manager module** regardless of the host's OS. Same file shape across NixOS + standalone — no platform-specific module conventions inside `home.nix`.

`home/core.nix` is the shared user-scope baseline imported by every machine's `home.nix` via `imports = [ ../../home/core.nix ]`. Cross-platform CLI + identity (starship, programs.git, comma, sops/age/claude-code, just/ripgrep/tmux).

## Concerns compose host identity

`modules/<concern>/` directories represent host roles. A host's identity is the sum of which concerns it imports plus its hardware:

| Concern | What it adds | Imported by |
|---|---|---|
| `common/` | Universal infra: base, users, Tailscale, sops + the `effects/` interface options | every host |
| `services/` | *This host serves things*: Caddy, Authelia, *arr, backups, media, monitoring | pi (whole bundle for the entry plane); aurora (whole bundle for family-tier backends); workstation (whole bundle for compute-side services) |
| `desktop/` | *This host has a graphical session*: Hyprland, greetd, audio | workstation; future `nori-laptop` |
| `effects/` | Reader + Writer interface options | imported by `common/`; populated by hosts (Reader) and services (Writer) |

A typical NixOS host file:

```nix
# machines/workstation/default.nix
imports = [
  inputs.disko.nixosModules.disko
  ../../modules/common
  ../../modules/services
  ../../modules/desktop
  ./hardware.nix
  ./disko.nix
];
```

Reading this answers "what kind of machine is `workstation`?" at a glance. `pi` lives as `common +` *flat imports of specific server modules* (Blocky, Gatus, Beszel hub+agent, ntfy server+notify) — the bundle import is too coarse for the appliance role.

### Coupling vs categorization

**Within `modules/services/`, folders signal coupling, not categorization.** Tightly-coupled clusters get their own folder + `default.nix`:

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
  nori.backups.<service>.include = [ "/var/lib/<service>" ];
  # or for stateless / re-derivable services:
  # nori.backups.<service>.skip = "<reason>";

  # SQLite-backed services: use Pattern C2 (VACUUM INTO + flock)
  # See modules/services/navidrome.nix for canonical impl + SERVICES.md § Pattern C2.

  # Optional: open backend port directly on tailnet (default: closed)
  # nori.lanRoutes.<short-name>.exposeOnTailnet = true;
}
```

**After landing:**

```
just preview      → activate without boot entry
just test         → runs all introspection tests (test-hypr / -backups / -routes / -observability)
just show-pending-diff      → review diff before push
just rebuild      → persist
```

## Filesystem hardening (`nori.harden`)

The default-deny systemd FS-namespace block (`ProtectHome = mkForce true`, `TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ]`, plus `BindPaths` / `BindReadOnlyPaths` for what's let back in) lives behind the `nori.harden` abstraction in `modules/infra/capabilities/default.nix`.

```nix
nori.harden.<unit> = {
  binds         = [ /* writable host paths */ ];
  readOnlyBinds = [ /* read-only host paths */ ];
  protectHome   = true | false | null;  # default true; null skips
};
```

The `every-service-has-fs-hardening` flake check fails the build if any `modules/services/*.nix` is missing a `nori.harden.<n>` declaration (excluded list: aggregators, framework, ntfy/notify, samba's legitimate /srv exception).

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

Canonical doc: `modules/services/arr/shared.nix` header comment.

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
| `StateDirectory` is `/var/lib/private/<name>` symlinked to `/var/lib/<name>` | Target the real path: `nori.backups.<n>.paths = [ "/var/lib/private/<name>" ];`. Restic stores symlinks AS symlinks → pointing at `/var/lib/<name>` produces a 0-byte snapshot. A self-maintaining assertion in `modules/infra/backup/default.nix` (derived from `config.systemd.services` introspection) catches this at eval time. Deep dive: `.claude/skills/gotcha-dynamicuser-statedirectory-symlink/` |

Adding a new OIDC client → `/add-oidc-client` (procedure skill — bootstrap, sops paste, route declaration, systemd wiring).

## Packages: where things live by scope

Packages and config live at one of four scopes. Pick the **lowest** scope that gets the tool to its actual audience — drift goes the other way (a tool only the operator uses ends up at system scope and has to be moved later).

| Scope | Where | Audience | Examples |
|---|---|---|---|
| **System floor** | `modules/common/base.nix` `environment.systemPackages` | Every host (incl. pi, which has no home-manager); root, sshd, system services | `bat curl dig fd git htop just ripgrep tmux tree vim wget` |
| **System desktop** | `modules/desktop/apps.nix` `environment.systemPackages` + `fonts.packages` | Workstation Linux desktop session — Hyprland-invoked apps, GUI clients, fonts | `ghostty fuzzel hyprpaper zen bitwarden-desktop zed-editor davinci-resolve nerd-fonts.jetbrains-mono` |
| **User core** | `home/core.nix` `home.packages` + `programs.<x>` | Every interactive machine where nori is the operator | `comma starship programs.git age sops claude-code` |
| **Per-machine user** | `machines/<host>/home.nix` `home.packages` | One specific machine | workstation: `nvtop` (NVIDIA), `compsize` (btrfs), Hyprland binds; Mac: `bun pnpm ffmpeg`, `home.file."Library/Fonts/..."` |

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
just show-status                   # failed units + disk + restic/btrbk timer summary
just show-logs <unit>              # last 50 journal lines
just check                    # nix flake check
just deploy                   # git push + nh os switch from origin (no rsync)
just rollback                 # previous generation
just backup <repo>            # immediately run restic-backups-<repo>
just list-snapshots <repo>         # list restic snapshots
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

Detailed step-by-step in `docs/installs/baremetal.md`. `nixos-anywhere` is the fully-remote alternative.

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
