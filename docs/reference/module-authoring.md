---
summary: Repository structure, service module template, FS hardening (`nori.harden`),
  sops patterns, packages-by-scope, dev shells, commit + code style. The "how the
  code is shaped" reference. Rules ABOUT modules live in docs/invariants.md.
---

# Module authoring

Repository-wide patterns for *writing* modules. Rules and how they're checked live in `docs/invariants.md`; this file is the shape of the code itself.

## Repository structure

```
flake.nix                          dep injection + thin output wiring
flake.lock                         Pinned 26.05 revision; reproducibility
machines/                          per-host NixOS system config
  workstation/  pi/  pavilion/     NixOS hosts (default + hardware +
  aurora/                          disko + home.nix)
  macbook/                         standalone home-manager (no NixOS)
home/                              home-manager modules — user-space
  core.nix                         cross-platform CLI baseline
  pc.nix                           operator-PC tier — heavy closures
  claude-code/                     CLI + skills/ + settings.json
  hermes/                          Hermes Agent CLI (Linux-only)
modules/
  machines/                        nixosConfigurations factory
    default.nix                    enumeration + mkHost + identityFor
                                   + hostRegistry
  home/                            homeConfigurations factory
    default.nix                    macbook (standalone home-manager)
  common/                          universal — every host imports
    base.nix · users.nix ·         baseline OS bits + the infra layer
    sops.nix · tailscale.nix       (imports of ../infra/<concern>/)
  infra/                           PaaS platform — the hosting layer
    backup/                        nori.backups schema + restic +
                                   btrbk + verify adapters
    storage/                       nori.fs + nori.replicas
    networking/                    nori.lanRoutes + Caddy + Blocky
    access/                        Authelia (audience IAM)
    capabilities/                  nori.harden + nori.gpu (what a
                                   service can DO on the machine)
    observability/                 Gatus + Victoria* + Beszel + ntfy
                                   + exporters + Grafana + vector
                                   + heartbeat + disk-alert
    hosts.nix                      nori.hosts schema (registry)
    placement.nix                  role × backup compatibility
    resource-tiers.nix             memory-tier defaults
    restart-policy.nix             systemd restart defaults
    tailnet-appliance.nix          appliance hardening defaults
    motd.nix                       codename banner + live MOTD
  services/                        workloads — what the operator runs
    <workload>.nix                 vaultwarden, navidrome, immich,
                                   ollama, jellyfin, calibre-web,
                                   komga, radicale, miniflux,
                                   glance, heim, filmder, hermes,
                                   open-webui, stremio, syncthing,
                                   samba
    arr/                           coupled cluster — Sonarr/Radarr/
                                   Lidarr/Bazarr/Jellyseerr/Prowlarr/
                                   qBittorrent (cross-reference via
                                   API + shared media group)
    default.nix                    workload bundle aggregator
  desktop/                         GUI session — Hyprland, Stylix, …
  dev/                             dev-shell fragments (mkDevShell)
  lint/                            code-quality dispatcher
secrets/
  secrets.yaml · apps.yaml ·       sops-encrypted
  .sops.yaml
docs/
  decisions/                       ADRs — hard-to-reverse choices
  runbooks/                        per-failure recovery
  reference/                       tier-2 reference docs
  plans/ · reports/ · specs/       forward-looking + retrospective
.claude/
  skills/                          procedure skills (load on demand)
```

**Layout principle (PaaS lens):** the homelab IS a hosting provider for self-hosted family-tier services. The split mirrors what a PaaS layers:

- `modules/services/` — **workloads** (what the operator USES: vaultwarden, immich, jellyfin, …). User-facing applications consuming the platform.
- `modules/infra/` — **platform** (HOW the system works: storage, networking, access control, observability, backup, capabilities). The hosting layer.
- `modules/machines/` — composition (per-host module list + identity).
- `modules/home/` + `home/` — home-manager (user-space + standalone Mac).
- `modules/machines/base/` — universal NixOS bits + imports of the infra layer.

Workloads in `services/` depend on infra concerns; infra concerns depend on `machines/` (the hosts they run on). No upward dependencies; no cycles.

## Configuration derivation from layout

The flake derives configurations from the directory structure:

| Detected | Produces |
|---|---|
| `modules/machines/<n>/default.nix` | `nixosConfigurations.<n>` (NixOS host) |
| `modules/machines/<n>/home.nix` without `default.nix` | `homeConfigurations.<n>` (e.g. Mac; activated via standalone home-manager) |
| NixOS hosts that have `home.nix` | Activate via `home-manager-as-NixOS-module` inside their own `default.nix` |

`modules/machines/<n>/home.nix` is a **pure home-manager module** regardless of the host's OS. Same file shape across NixOS + standalone — no platform-specific module conventions inside `home.nix`.

`modules/home/core.nix` is the shared user-scope baseline imported by every machine's `home.nix` via `imports = [ ../../home/core.nix ]`. <!-- path-coherence: skip — illustrative import string (quoted as it appears in machines/*/home.nix, not resolved from this doc's location) --> Cross-platform CLI + identity (starship, programs.git, comma, sops/age/claude-code, just/ripgrep/tmux).

## Concerns compose host identity

`modules/<concern>/` directories represent host roles. A host's identity is the sum of which concerns it imports plus its hardware:

| Concern | What it adds | Imported by |
|---|---|---|
| `common/` | Universal infra: base, users, Tailscale, sops + the `effects/` interface options | every host |
| `services/` | *This host serves things*: Caddy, Authelia, *arr, backups, media, monitoring | pi (whole bundle for the entry plane); aurora (whole bundle for family-tier backends); workstation (whole bundle for compute-side services) |
| `desktop/` | *This host has a graphical session*: Hyprland, greetd, audio | workstation; future `nori-laptop` |
| `effects/` | Reader + Writer interface options | imported by `common/`; populated by hosts (Reader) and services (Writer) |

A typical NixOS host file (workstation, post-Phase-6):

<!-- path-coherence: skip-block — illustrative fenced example; ./hardware.nix and ./disko.nix are siblings of the host file shown in the comment header (modules/machines/workstation/), not this doc -->

```nix
# modules/machines/workstation/default.nix
imports = [
  inputs.disko.nixosModules.disko
  inputs.home-manager.nixosModules.home-manager

  ../base       # base + users + sops + tailscale + lib options
  ../../services # every server module (HTTP, *arr, backup, …)
  ../desktop    # Hyprland + greetd + audio + bars + apps + gaming

  ./hardware.nix
  ./disko.nix
];
```

<!-- path-coherence: end-skip -->

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
| **System floor** | `modules/machines/base/base.nix` `environment.systemPackages` | Every host (incl. pi, which has no home-manager); root, sshd, system services | `bat curl dig fd git htop just ripgrep tmux tree vim wget` |
| **System desktop** | `modules/machines/desktop/apps.nix` `environment.systemPackages` + `fonts.packages` | Workstation Linux desktop session — Hyprland-invoked apps, GUI clients, fonts | `ghostty fuzzel hyprpaper zen bitwarden-desktop zed-editor davinci-resolve nerd-fonts.jetbrains-mono` |
| **User core** | `modules/home/core.nix` `home.packages` + `programs.<x>` | Every interactive machine where nori is the operator | `comma starship programs.git age sops claude-code` |
| **Per-machine user** | `modules/machines/<host>/home.nix` `home.packages` | One specific machine | workstation: `nvtop` (NVIDIA), `compsize` (btrfs), Hyprland binds; Mac: `bun pnpm ffmpeg`, `home.file."Library/Fonts/..."` |

Decision rules:

- Needed by root / system services / pi? → **system floor**
- Coupled to the Linux desktop session (Hyprland binds, fontconfig, GUI launchers)? → **system desktop**
- Interactive operator tool, every machine? → **user core**
- Machine-specific? → **per-machine user**

Acceptable cross-scope overlap: `git` lives in both `base.nix` (for root + Nix's flake operations) and `core.nix` `programs.git` (for the operator's per-user config). Both load-bearing.

What does NOT belong in `core.nix`: anything platform-specific (NVIDIA tools, Wayland-only programs, Linux fontconfig). Cross-platform CLI only — if the tool doesn't build on `x86_64-darwin`, it's not core.

## Dev shells

Dev environments are a per-project concern, not a homelab capability. Each repo owns its own (devenv / direnv / `nix shell` / project flake `devShells`). The homelab repo itself has a lean `devShells.default` for editing — `nixfmt`, `statix`, `deadnix`, `nh`, `ripgrep`. No cross-project shell library lives here anymore.

## Dev workflow

`Justfile` at repo root for common workflows. Install: `pkgs.just` already in `modules/machines/base/base.nix`; `brew install just` on macOS.

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

Disk layouts in `modules/machines/<host>/disko*.nix` from day zero. First install:

1. Boot NixOS minimal installer USB
2. SSH into installer or work locally
3. Clone the flake to `/tmp/homelab`
4. `nix --experimental-features 'nix-command flakes' run github:nix-community/disko/latest -- --mode disko /tmp/homelab/modules/machines/workstation/disko.nix`
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
