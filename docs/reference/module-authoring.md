---
summary: Repository structure, service module template, FS hardening (`nori.harden`),
  sops patterns, packages-by-scope, dev shells, commit + code style. The "how the
  code is shaped" reference. Rules ABOUT modules live in docs/invariants.md.
---

# Module authoring

Repository-wide patterns for *writing* modules. Rules and how they're checked live in `docs/invariants.md`; this file is the shape of the code itself.

## Repository structure

```
flake.nix                          inputs + thin flake-parts composition
flake-parts/                       output concerns: machines, homes, packages,
                                   checks, formatter, dev shell
inventory/                         pure pre-module control plane
  hosts.nix                        identity, profiles, local deviations
  profiles.nix                     explicit reusable system compositions
  workloads.nix                    manifest aggregation
  datasets.nix                     authoritative shared-data contracts
  site.nix                         canonical and deprecated namespaces
  default.nix                      compiler + public-safe projections
modules/
  machines/                        NixOS factory + host realizations
    default.nix                    inventory-backed mkHost
    base/ desktop/                 reusable low-level system modules
    <host>/                        hardware, storage, local deviations, home
  profiles/                        reusable system capability adapters
  infra/                           PaaS platform — the hosting layer
    inventory.nix                  typed injected inventory projection
    backup/ storage/ networking/   collected intent + runtime adapters
    access/ observability/
    capabilities/                  service filesystem/GPU capabilities
    hosts.nix                      compatibility host identity projection
  services/                        hosted workloads
    <workload>/manifest.nix        pure catalog + endpoint metadata
    <workload>/runtime.nix         local NixOS realization + effects
    arr/                           intentionally coupled acquisition cluster
  home/                            Home Manager capabilities and profiles
    profiles/core.nix              smallest interactive-user baseline
    profiles/development/          global and security-sensitive agent tools
    profiles/desktop/              session, productivity, communication, research
    profiles/creative/             audio and video capabilities
    desktop/hypr-rice/             public option + private rice runtime/tests
tests/                             eval, fixtures, VM/e2e, runtime recipes
scripts/                           checks, deployment planner, operator tools
secrets/
  secrets.yaml · apps.yaml         sops-encrypted; excluded from projections
docs/
  roadmap.md                       outcome backlog
  specs/ · decisions/              accepted designs + durable rationale
  reference/ · runbooks/           current truth + executable operations
  plans/ · reports/                retained plans + retrospective evidence
.claude/
  skills/                          procedure skills (load on demand)
```

**Layout principle (PaaS lens):** the homelab IS a hosting provider for self-hosted family-tier services. The split mirrors what a PaaS layers:

- `inventory/` — **control plane**: secret-free identity, placement, manifests,
  datasets, and projections evaluated before the NixOS fixed point.
- `modules/services/` — **workloads**: pure manifests plus local runtime
  realizations for applications consuming the platform.
- `modules/infra/` — **platform** (HOW the system works: storage, networking, access control, observability, backup, capabilities). The hosting layer.
- `modules/profiles/` — **system compositions** selected explicitly by inventory.
- `modules/machines/` — **realizations**: hardware, storage, local deviations,
  and the inventory-backed configuration factory.
- `modules/home/` — **user capabilities** and standalone/NixOS Home Manager
  compositions.

Dependency direction is inventory → platform/profile selection → realization.
Runtime modules write narrow local effects such as `nori.backups` and
`nori.harden`; cross-host consumers read the injected inventory rather than
importing every runtime.

## Configuration derivation from inventory

`inventory/hosts.nix` explicitly enumerates every NixOS and standalone Home
Manager target. `modules/machines/default.nix` compiles profile modules and
selected workload runtimes before calling `lib.nixosSystem`; it never chooses
imports from `config` or descriptive tags.

| Inventory kind | Produces |
|---|---|
| `kind = "nixos"` | `nixosConfigurations.<name>` plus an ordered deployment target |
| `kind = "home-manager"` | `homeConfigurations.<name>` plus a build-only deployment target |

Every NixOS host gets the same shared Home Manager wrapper from the factory and
imports its declared `homeModule`. Standalone entries use
`modules/home/default.nix`. Host home files remain ordinary Home Manager modules
on both operating systems.

## Concerns compose host identity

Host identity is the explicit sum of inventory profiles, selected workloads,
hardware/storage realization, and genuine local deviations:

| Concern | What it adds | Imported by |
|---|---|---|
| inventory profile | Reusable system modules and workload identifiers | hosts selecting that capability |
| workload manifest | Global ID, tags, endpoints, audience, artifact contract | inventory and presentation/deployment consumers |
| workload runtime | Units, secrets, hardening, backup and local effects | selected placement hosts only |
| machine realization | Hardware, disks, boot, host-specific overrides | one physical host |
| Home capability profile | Composable operator tools and desktop/product capabilities | selected home modules |

A typical host inventory entry:

<!-- path-coherence: skip-block — illustrative fenced example; ./hardware.nix and ./disko.nix are siblings of the host file shown in the comment header (modules/machines/workstation/), not this doc -->

```nix
# inventory/hosts.nix
workstation = {
  kind = "nixos";
  systemModule = ../modules/machines/workstation;
  homeModule = ../modules/machines/workstation/home.nix;
  profiles = [ "base" "desktop" "media-compute" "observability-agent" ];
  workloads = [ "gatus" "disk-alert" ]; # genuine deviations only
  identity = { /* public-safe topology */ };
};
```

<!-- path-coherence: end-skip -->

`inventory/profiles.nix` is the reviewed composition surface. Tags describe and
support queries; they never deploy a runtime.

### Coupling vs categorization

Within `modules/services/`, folders usually own one manifest/runtime pair.
Additional nesting signals real implementation coupling, not a loose category:

| Cluster | Coupling |
|---|---|
| `arr/` | Sonarr/Radarr/Lidarr/Bazarr/Jellyseerr/Prowlarr/qBittorrent — reference each other via API; share `/mnt/media/streaming` via the `media` group + `arr/shared.nix` tmpfiles |
| single workload directory | `manifest.nix` is global and pure; `runtime.nix` is placement-local |

Infrastructure-owned daemons such as Caddy, Blocky, exporters, and alerting keep
their manifests next to their platform adapter. The compiler aggregates both
locations explicitly in `inventory/workloads.nix`.

## Workload manifest and runtime template

The manifest is safe to evaluate on every host and in CI/documentation. It must
contain no secret values, host-local state, or NixOS `config` dependency.

<!-- path-coherence: skip-block — illustrative workload paths -->

```nix
# modules/services/example/manifest.nix
{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [ "family-tier" ];
  endpoints.example = {
    port = 1234;
    audience = "family";
    noAuthReason = "Native clients use service accounts";
    monitor = { };
    dashboard = {
      title = "Example";
      description = "What family members use it for";
      group = "Consume";
      icon = "example";
    };
  };
}
```

The runtime owns local implementation and collected effects:

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

  # Backup intent (required — `every-service-has-backup-intent` flake check)
  nori.backups.<service>.include = [ "/var/lib/<service>" ];
  # or for stateless / re-derivable services:
  # nori.backups.<service>.skip = "<reason>";

  # SQLite-backed services: use Pattern C2 (VACUUM INTO + flock)
  # See modules/services/navidrome/runtime.nix for canonical implementation.
}
```

Add the manifest to `inventory/workloads.nix`, then place its identifier in one
explicit profile or host deviation. Never activate from a tag or directory scan.

<!-- path-coherence: end-skip -->

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
| **System desktop** | `modules/machines/desktop/` | System/session integration, display manager, drivers, audio, fonts | Hyprland, greetd, PipeWire, Stylix, Sunshine |
| **User core** | `modules/home/profiles/core.nix` | Every interactive machine where nori is the operator | starship, Git, direnv, common CLI baseline |
| **User capability** | `modules/home/profiles/{desktop,creative,development}/` | Homes selecting a coherent reusable capability | communication, research, video, audio, global development, agentic tools |
| **Per-machine user** | `modules/machines/<host>/home.nix` `home.packages` | One specific machine | workstation: `nvtop` (NVIDIA), `compsize` (btrfs), Hyprland binds; Mac: `bun pnpm ffmpeg`, `home.file."Library/Fonts/..."` |

Decision rules:

- Needed by root / system services / pi? → **system floor**
- Required to create the Linux graphical system/session? → **system desktop**
- Interactive operator tool, every machine? → **user core**
- Reusable user-facing function with its own security or product concern? → **user capability**
- Machine-specific? → **per-machine user**

Acceptable cross-scope overlap: `git` lives in both `base.nix` (for root + Nix's flake operations) and `core.nix` `programs.git` (for the operator's per-user config). Both load-bearing.

What does NOT belong in the core profile: anything platform-specific (NVIDIA
tools, Wayland-only programs, Linux fontconfig), creative suites, or coding-agent
runtimes. Agent runtimes and sandbox policy are a separate security-sensitive
capability.

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
just plan-deploy origin/main  # read-only affected-host/build plan
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
| Attribution | Follow the active agent/provider policy; do not invent a co-author |
| Formatter | `nixfmt` (set as the flake formatter) |
| Linter | `statix` (anti-patterns) + `deadnix` (unused bindings) |
| Pre-commit | `.githooks/pre-commit` runs `nix flake check`; skips gracefully if nix isn't on PATH (Mac case); CI catches the skipped commits |
| Branching | Small routine changes may remain atomic on `main`; multi-phase or high-blast-radius migrations use a worktree branch and operator-reviewed PR |
