---
summary: Repository structure, service module template, FS hardening (`nori.harden`),
  sops patterns, packages-by-scope, dev shells, commit + code style. The "how the
  code is shaped" reference. Rules ABOUT modules live in docs/invariants.md.
---

# Module authoring

Repository-wide patterns for *writing* modules. Rules and how they're checked live in `docs/invariants.md`; this file is the shape of the code itself.

## Repository structure

```text
inventory/                    shared hosts, workloads, profiles, backup and dataset facts
services/                     direct service manifests and concrete realizations
infra/
  workstation/               workstation hardware, disks and physical bindings
  pi/                        Ansible appliance, inventory adapter and VM tests
  common/                    shared NixOS and Ansible host mechanisms
  cloudflare/                external infrastructure configuration
profiles/                     reusable NixOS and Home Manager compositions
users/nori/                   identity, Home Manager selection and program implementations
roles/                        shared access-policy vocabulary
lib/                          flake outputs, host factory and documentation helpers
secrets/                      encrypted values and operator procedures
tests/                        shared evaluation and integration checks
scripts/                      cross-project operator utilities
docs/
  reference/ runbooks/         current architecture and executable operations
  specs/ decisions/           accepted contracts and durable rationale
  generated/                  reproducible inventory and schema projections
  archive/                    historical plans and reports
```

**Layout principle (PaaS lens):** the homelab IS a hosting provider for self-hosted family-tier services. The split mirrors what a PaaS layers:

- `inventory/` — **control plane**: secret-free identity, placement, manifests,
  datasets, and projections evaluated before the NixOS fixed point.
- `services/` — **workloads**: a pure manifest, shared implementation, and each
  concrete realization that actually exists. `services/music-ingest/nixos.nix`
  is the first direct realization; no dispatcher or empty backend matrix sits
  in front of it.
- `infra/common/nixos/` — **platform**: shared storage, networking, access,
  observability, backup, and capability mechanisms.
- `profiles/` — **reusable compositions** selected explicitly by inventory.
- `infra/<machine>/` — **physical bindings**: paths, filesystem identities,
  and integration that varies with one concrete machine.
- `users/<name>/` — **identity and preferences**: Home Manager selection and
  program implementations owned by one user.
- `roles/` — **access policy vocabulary** used by schemas and presentation.
- `lib/` — **evaluation and build helpers**; it contains no runtime ownership.

Dependency direction is inventory → platform/profile selection → realization.
Runtime modules write narrow local effects such as `nori.backups` and
`nori.harden`; cross-host consumers read the injected inventory rather than
importing every runtime.

## Configuration derivation from inventory

`inventory/hosts.nix` explicitly enumerates each managed host, its deployment
owner, profiles, and placement tags. Service manifests own ordered placement
selectors. The inventory compiler resolves them before `lib/machines.nix`
selects NixOS runtime modules; imports never depend on `config`.

| Inventory kind | Produces |
|---|---|
| `kind = "nixos"` | `nixosConfigurations.<name>` plus an ordered deployment target |
| `kind = "ansible"` | explicit `plan`, `apply`, and `verify` commands; never a `nixosConfiguration` or Nix build target |

Every NixOS host gets the same shared Home Manager wrapper from the factory and
imports its declared `homeModule`. Ansible hosts retain profiles for shared
inventory classification, but their system realization is owned exclusively by
their declared management root and deployment commands.

## Concerns compose host identity

Host identity combines inventory profiles, placement tags, hardware/storage
realization, and genuine local deviations:

| Concern | What it adds | Imported by |
|---|---|---|
| inventory profile | Reusable system modules | hosts selecting that capability |
| workload manifest | Global ID, ordered placement selectors, tags, endpoints, audience, artifact contract | inventory and presentation/deployment consumers |
| workload runtime | Units, secrets, hardening, backup and local effects | resolved realization hosts only |
| machine realization | Hardware, disks, boot, host-specific overrides | one physical host |
| Home capability profile | Composable operator tools and desktop/product capabilities | selected home modules |

A typical host inventory entry:

<!-- path-coherence: skip-block — illustrative fenced example; ./hardware.nix and ./disko.nix are siblings under infra/workstation/, not this doc -->

```nix
# inventory/hosts.nix
workstation = {
  kind = "nixos";
  managementRoot = "infra/workstation";
  systemModule = ../infra/workstation;
  homeModule = ../users/nori/home.nix;
  profiles = [ "base" "desktop" "media-compute" "observability-agent" ];
  tags = [ "nixos" "primary-service-host" ];
  identity = { /* public-safe topology */ };
};
```

<!-- path-coherence: end-skip -->

`profiles/default.nix` selects reusable system modules. Host tags are typed
placement inputs. Workload tags remain descriptive metadata.

### Coupling vs categorization

Within `services/`, one folder owns a service's manifest, implementation, and
real realizations. Name the varying dimension in the file: `nixos.nix` means
the NixOS realization. Add another file or directory only when a second actual
realization needs it; do not pre-create a Cartesian hierarchy.

| Cluster | Coupling |
|---|---|
| `profiles/media-acquisition/` | `members.nix` owns the acquisition-stack membership and deployment roots; `nixos.nix` imports those members with shared resources, and each child enables only when its workload appears in `currentWorkloads` |
| direct workload directory | `manifest.nix` is global and pure; `nixos.nix` is the deployable NixOS realization |

Infrastructure-owned daemons such as Caddy, Pi-hole, exporters, and alerting
keep their manifests next to their platform adapter. The compiler aggregates
both locations explicitly in `inventory/workloads.nix`.

## Workload manifest and runtime template

The manifest is safe to evaluate on every host and in CI/documentation. It must
contain no secret values, host-local state, or NixOS `config` dependency.

<!-- path-coherence: skip-block — illustrative workload paths -->

```nix
# services/example/manifest.nix
{
  kind = "service";
  hostRoles = [ "workhorse" ];
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "primary-service-host" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  runtimeModule = ./nixos.nix;
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

The concrete realization owns its backend translation and collected effects:

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
  # See services/navidrome/nixos.nix for canonical implementation.
}
```

Add the manifest to `inventory/workloads.nix`. Its ordered selectors are the
only placement authority. Use `first-unique` for a singleton or an ordered
fallback. Use `all-matches` only for an explicit per-host workload, with fixed
cardinality. The compiler rejects unknown selectors, ambiguous singletons,
role violations, and endpoint workloads without exactly one realization.

<!-- path-coherence: end-skip -->

**Verify, then activate within operator authorization:**

```
just check        → fast Nix checks
just build        → build without activation
just activate-test → change live system without boot entry
just test         → runs all introspection tests (test-hypr / -backups / -routes / -observability)
just show-pending-diff      → review diff before push
just rebuild      → persist
```

## Filesystem hardening (`nori.harden`)

The default-deny systemd FS-namespace block (`ProtectHome = mkForce true`, `TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ]`, plus `BindPaths` / `BindReadOnlyPaths` for what's let back in) lives behind the `nori.harden` abstraction in `infra/common/nixos/service-hardening.nix`.

```nix
nori.harden.<unit> = {
  binds         = [ /* writable host paths */ ];
  readOnlyBinds = [ /* read-only host paths */ ];
  protectHome   = true | false | null;  # default true; null skips
};
```

The `every-service-has-fs-hardening` flake check scans concrete catalog service
modules under `services/` and fails when one lacks a `nori.harden.<n>`
declaration. Aggregators, manifests, ntfy/notify, Samba's legitimate `/srv`
exception, and OS mechanisms that were outside the pre-migration catalog scan
are excluded explicitly. Expanding that policy to those mechanisms requires a
separate state, backup, and namespace audit; the reorganization does not invent
new policy to satisfy a wider filesystem scan.

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

Services that share media files join the `media` group while each service keeps
its own user ID. The group and setgid directories provide shared read and write
access.

Sonarr and Radarr import into directories on `@downloads`. They can hardlink
completed files from qBittorrent because the source and target share a
subvolume. Lidarr imports into `@library/music`, which is a different subvolume.
Do not claim that Lidarr uses hardlinks across that boundary.

The authoritative paths and permissions are in
`profiles/media-acquisition/resources.nix` and each service module.

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
| `StateDirectory` is `/var/lib/private/<name>` symlinked to `/var/lib/<name>` | Target the real path: `nori.backups.<n>.include = [ "/var/lib/private/<name>" ];`. Restic stores the symlink when a job targets `/var/lib/<name>`, which produces a 0-byte state snapshot. `infra/common/nixos/backup.nix` derives an assertion from the evaluated systemd services and rejects this path. |

Adding a new OIDC client → `/add-oidc-client` (procedure skill — bootstrap, sops paste, route declaration, systemd wiring).

## Packages: where things live by scope

Packages and config live at one of four scopes. Pick the **lowest** scope that gets the tool to its actual audience — drift goes the other way (a tool only the operator uses ends up at system scope and has to be moved later).

| Scope | Where | Audience | Examples |
|---|---|---|---|
| **System floor** | `infra/common/nixos/base.nix` `environment.systemPackages` | NixOS hosts; root, sshd, system services | `bat curl dig fd git htop just ripgrep tmux tree vim wget` |
| **System desktop** | `profiles/desktop/nixos/` | System/session integration, display manager, drivers, audio, fonts | Hyprland, greetd, PipeWire, Stylix, Sunshine |
| **User core** | `profiles/home/core.nix` | Every interactive machine where nori is the operator | starship, Git, direnv, common CLI baseline |
| **User capability** | `profiles/home/{desktop,creative,development}/` | Homes selecting a coherent reusable capability | communication, research, video, audio, global development, agentic tools |
| **Per-machine user** | `users/nori/workstation.nix` `home.packages` | One specific machine | workstation: `nvtop` (NVIDIA), `compsize` (btrfs), Hyprland binds |

Decision rules:

- Needed by NixOS root / system services? → **system floor**; Pi packages belong in Ansible roles.
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

Dev environments are a per-project concern, not a homelab capability. Each repo owns its own (devenv / direnv / `nix shell` / project flake `devShells`). For this repo, `devenv shell` is the preferred explicit entry point and `.envrc` selects the same environment automatically. It includes the tools used by the documented workflows and runs the music-ingest runtime suite through `devenv test`. The lean `devShells.default` remains available through `nix develop` for compatibility. No cross-project shell library lives here anymore.

## Dev workflow

`Justfile` at repo root for common workflows. Install: `pkgs.just` already in `infra/common/nixos/base.nix`; `brew install just` on macOS.

```sh
just                          # default: list available operator commands
just --list                   # inspect arguments for the selected recipe
just show-status                   # failed units + disk + restic/btrbk timer summary
just show-logs <unit>              # last 50 journal lines
just check                    # nix flake check
just plan-deploy <comparison-base> # read-only plan; choose main, upstream, or the deployed commit
just deploy                   # switch the current host from github:phibkro/homelab; does not push
just rollback                 # previous generation
just backup <repo>            # immediately run restic-backups-<repo>
just list-snapshots <repo>         # list restic snapshots
just --list                   # all recipes
```

`nh os switch` activates local or GitHub-sourced workstation generations. It invokes sudo internally, so do not prefix it. The remote `push <host>` recipe uses `nixos-rebuild --target-host` instead.

Local `rebuild` targets the current NixOS host. Use `push <host>` for an
explicit remote NixOS target. Pi has its own `pi::` commands; do not pass Pi to
a NixOS rebuild recipe. Inspect `just --list` for each recipe's arguments.

### Pi is an Ansible target

Use `just pi::check`, `just pi::test`, and `just pi::plan` before an approved,
target-confirmed `just pi::deploy`. The
[deployment reference](deployment.md) defines the required confirmation value.
Pi has no production `nixosConfigurations.pi` and no NixOS closure to
cross-build. Nix entry-plane adapter tests cover shared contracts; they do not
test production Ansible behavior.

### Disko at install

Disk layouts live in `infra/<host>/disko*.nix` from day zero. A workstation
install must:

1. boot a NixOS minimal installer;
2. obtain the intended repository revision and existing `flake.lock`;
3. identify every attached disk by model, serial, and `/dev/disk/by-id/`;
4. confirm that the evaluated disko scope contains only the approved target;
5. apply `infra/workstation/disko.nix`;
6. run `nixos-install --flake /tmp/homelab#workstation`;
7. restore or re-enroll host identity before activating secret-dependent units.

Formatting a disk, changing SOPS recipients, and enrolling Tailscale are
separate operator-authorized effects. The current procedure and preservation
constraints are in `docs/installs/baremetal.md` and
`docs/runbooks/drive-failure-root.md`.

## Commit + code style

| Layer | Rule |
|---|---|
| Conventional Commits | `type(scope): summary` |
| Body | Explain *why* and what was tried |
| Attribution | Follow the active agent/provider policy; do not invent a co-author |
| Formatter | `nixfmt` (set as the flake formatter) |
| Linter | `statix` (anti-patterns) + `deadnix` (unused bindings) |
| Pre-commit | `.githooks/pre-commit` checks an isolated snapshot of the exact index with fast Nix and Pi static checks; missing tools fail explicitly; it never fixes the working tree |
| Branching | Small routine changes may remain atomic on `main`; multi-phase or high-blast-radius migrations use a worktree branch and operator-reviewed PR |
