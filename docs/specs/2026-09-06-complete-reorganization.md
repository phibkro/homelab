# Complete repository reorganization contract

Frozen source: `4f4dcabb746497578df84d3252b71b47bafd4cd8`.

This is a structural migration. Package pins, host identity, workload placement,
service enablement, ports, routes, audience/authentication policy, secrets,
storage paths, backup policy, timers, hardening, and deployment behavior must
remain unchanged. The only accepted parity differences are repository paths and
path-derived deployment source-root keys. There are no compatibility wrappers
after acceptance, and the legacy `nix/` and `pi/` roots must be absent.

## Target ownership

```text
inventory/                 physical facts, placement, datasets, backup facts
profiles/                  reusable system and Home Manager compositions
roles/                     access/audience policy only
infra/common/{nixos,ansible}/ reusable host mechanisms
infra/workstation/         workstation hardware, storage, and host integration
infra/pi/                  Pi assembly, inventory generation, deployment, VM harness
services/<service>/        manifests and NixOS/Ansible realizations
users/nori/                identity, preferences, and program implementations
lib/                       flake/evaluation/build helpers
products/status/           independently developed status application
tests/                     cross-component behavior and parity tests
docs/generated/            generated projections; never an authority
```

The semantic flow stays:

```text
inventory facts + profile selection + role policy
                        |
                        v
          backend-specific realization
           /                         \
  infra/* + services/*/nixos   infra/pi + services/*/ansible
                        |
                        v
               observed host behavior
```

## Mechanical path mapping

These moves happen as one deterministic rename pass before import repair.

### Flake and host realization

| Old | New |
|---|---|
| `nix/flake-parts/**` | `lib/flake-parts/**` |
| `nix/lib/machines.nix` | `lib/machines.nix` |
| `nix/lib/nixdoc.nix` | `lib/nixdoc.nix` |
| `nix/hosts/workstation/default.nix` | `infra/workstation/default.nix` |
| `nix/hosts/workstation/{hardware,backup-storage,disko,disko-media,disko-mp510,resource-policy,waydroid}.nix` | `infra/workstation/{hardware,backup-storage,disko,disko-media,disko-mp510,resource-policy,waydroid}.nix` |
| `nix/hosts/workstation/home.nix` | split between `users/nori/home.nix` (composition/account defaults) and `users/nori/workstation.nix` (workstation packages, resource limits, and `/srv/nori` links) |
| `nix/AGENTS.md` | replaced by scoped routes in `AGENTS.md`, `infra/AGENTS.md`, `services/AGENTS.md`, and `users/AGENTS.md` |

`infra/workstation/{media-storage,music-ingest}.nix` and
`services/music-ingest/**` are already in their final ownership locations and
are preserved.

### Existing application services

For each name below, move `nix/modules/services/<name>/manifest.nix` to
`services/<name>/manifest.nix` and `runtime.nix` to
`services/<name>/nixos.nix`; preserve all other sibling implementation assets:

```text
attic calibre-web filmder glance heim herdr-projects-mcp hindsight immich
jellyfin komga mcp-origin-tunnel miniflux navidrome ollama open-webui paperless
radicale samba stremio suwayomi syncthing vaultwarden
```

`nix/modules/services/clamor/manifest.nix` moves to
`services/clamor/manifest.nix` (it has no local runtime). The shared helper
`nix/modules/services/lib.nix` moves to `lib/nixos/service.nix`.

The coupled acquisition stack keeps its current atomic activation behavior:

| Old | New |
|---|---|
| `nix/modules/services/arr/runtime.nix` | `profiles/media-acquisition/nixos.nix` |
| `nix/modules/services/arr/shared.nix` | `profiles/media-acquisition/resources.nix` |
| `nix/modules/services/arr/<name>.nix` | `services/<name>/nixos.nix` |
| `nix/modules/services/arr/manifests/<name>.nix` | `services/<name>/manifest.nix` |
| `nix/modules/services/arr/recyclarr/**` | `services/recyclarr/implementation/**` |

Here `<name>` is exactly `bazarr`, `jellyseerr`, `lidarr`, `prowlarr`,
`qbittorrent`, `radarr`, `recyclarr`, or `sonarr`. Every one of those manifests
continues to reference the same `profiles/media-acquisition/nixos.nix` module,
so inventory deduplication and the existing coupled lifecycle are unchanged.
Splitting activation into eight independent runtimes is outside this migration.

`nix/modules/services/services.just` moves to `tests/services.just`.

### Every child of `nix/modules/system`

| Old child | New owner |
|---|---|
| `access/authelia/manifest.nix` | `services/authelia/manifest.nix` |
| `access/authelia/runtime.nix` | `services/authelia/nixos.nix` |
| `access/default.nix` | removed; the common baseline imports the needed access mechanism directly |
| `backup/agent-fix.nix` | `services/agent-fix/nixos.nix` |
| `backup/backup.just` | `tests/backup.just` |
| `backup/btrbk.nix` | `services/btrbk/nixos.nix` |
| `backup/default.nix` | `infra/common/nixos/backup.nix` (declaration schema and generic generator) |
| `backup/restic.nix` | `services/restic-backup/nixos.nix` |
| `backup/restic-target/{manifest,runtime}.nix` | `services/restic-target/{manifest,nixos}.nix` |
| `backup/verify.nix` | `services/restore-drill/nixos.nix` |
| `base/default.nix` | `infra/common/nixos/default.nix` |
| `base/base.nix` | `infra/common/nixos/base.nix` |
| `base/sops.nix` | `infra/common/nixos/sops.nix` |
| `base/tailscale.nix` | `services/tailscale/nixos.nix` |
| `base/users.nix` user declaration and authorized keys | `users/nori/identity.nix` |
| `base/users.nix` SSH daemon and sudo policy | `infra/common/nixos/ssh.nix` |
| `capabilities/default.nix` | `infra/common/nixos/service-hardening.nix` |
| `capabilities/gpu.nix` | `infra/common/nixos/gpu.nix` |
| `desktop/default.nix` | `profiles/desktop/nixos/default.nix` |
| `desktop/{apps,audio,fonts,gaming,hyprland,stylix,virt}.nix` | `profiles/desktop/nixos/{apps,audio,fonts,gaming,hyprland,stylix,virt}.nix` |
| `desktop/greetd.nix` | `services/greetd/nixos.nix` |
| `desktop/sunshine.nix` | `services/sunshine/nixos.nix` |
| `hosts.nix` | `infra/common/nixos/hosts.nix` |
| `inventory.nix` | `infra/common/nixos/inventory.nix` |
| `motd.nix` | `infra/common/nixos/motd.nix` |
| `networking/default.nix` | `infra/common/nixos/routes.nix` |
| `networking/gatus-probe.nix` | `infra/common/nixos/gatus-probes.nix` |
| `networking/blocky/{manifest,runtime}.nix` | `services/blocky/{manifest,nixos}.nix` |
| `networking/caddy/{manifest,runtime}.nix` | `services/caddy/{manifest,nixos}.nix` |
| `networking/cloudflare-ddns/{manifest,runtime}.nix` | `services/cloudflare-ddns/{manifest,nixos}.nix` |
| `networking/networking.just` | `tests/networking.just` |
| `observability/alerts.nix` | `infra/common/nixos/alerts.nix` |
| `observability/default.nix` | removed; `infra/common/nixos/default.nix` imports `alerts.nix` directly |
| `observability/beszel/manifests/{agent,hub}.nix` | `services/beszel/manifests/{agent,hub}.nix` |
| `observability/beszel/{agent,hub}.nix` | `services/beszel/nixos/{agent,hub}.nix` |
| `observability/disk-alert/{manifest,runtime}.nix` | `services/disk-alert/{manifest,nixos}.nix` |
| `observability/gatus/{manifest,runtime}.nix` | `services/gatus/{manifest,nixos}.nix` |
| `observability/grafana/{manifest,runtime}.nix` | `services/grafana/{manifest,nixos}.nix` |
| `observability/grafana-dashboards/**` | `services/grafana/implementation/dashboards/**` |
| `observability/heartbeat/{manifest,runtime}.nix` | `services/heartbeat/{manifest,nixos}.nix` |
| `observability/node-exporter/{manifest,runtime}.nix` | `services/node-exporter/{manifest,nixos}.nix` |
| `observability/ntfy/manifests/{notify,server}.nix` | `services/ntfy/manifests/{notify,server}.nix` |
| `observability/ntfy/{notify,server}.nix` | `services/ntfy/nixos/{notify,server}.nix` |
| `observability/nvidia-gpu-exporter/{manifest,runtime}.nix` | `services/nvidia-gpu-exporter/{manifest,nixos}.nix` |
| `observability/vector.nix` | `services/vector/nixos.nix` |
| `observability/victorialogs/{manifest,runtime}.nix` | `services/victorialogs/{manifest,nixos}.nix` |
| `observability/victoriametrics/{manifest,runtime}.nix` | `services/victoriametrics/{manifest,nixos}.nix` |
| `observability/observability.just` | `tests/observability.just` |
| `research/papers-fetch/default.nix` | `users/nori/programs/papers-fetch/nixos.nix` |
| `research/papers-fetch/papers-fetch.py` | `users/nori/programs/papers-fetch/papers-fetch.py` |
| `restart-policy.nix` | `infra/common/nixos/restart-policy.nix` |
| `storage/default.nix` | `infra/common/nixos/storage/default.nix` |
| `storage/replication.nix` | `infra/common/nixos/storage/replication.nix` |

The desktop profile imports `services/greetd/nixos.nix` and
`services/sunshine/nixos.nix`. The common baseline imports service mechanisms
that were universally selected before (`tailscale`, `agent-fix`) without
changing enablement.

### User and profile ownership

| Old | New |
|---|---|
| `nix/home/profiles/**` | `profiles/home/**` |
| `nix/profiles/research.nix` | `profiles/research/nixos.nix` |
| `inventory/profiles.nix` | `profiles/default.nix` (authoritative composition registry; `inventory/default.nix` imports it directly) |
| `nix/home/core.nix` | `users/nori/programs/core.nix` |
| `nix/home/user-restart-policy.nix` | `users/nori/programs/user-restart-policy.nix` |
| `nix/home/saturation-alert.nix` | `users/nori/programs/saturation-alert.nix` |
| `nix/home/{agent-notify,agent-skills,agent-soul,claude-code,desktop,omp,omp-lsp}/**` | `users/nori/programs/{agent-notify,agent-skills,agent-soul,claude-code,desktop,omp,omp-lsp}/**` |

`profiles/home/**` remains reusable composition only; it imports implementations
from `users/nori/programs/**`. `users/nori/home.nix` owns the selected profile
set, Home Manager state version, and account preferences.
`users/nori/workstation.nix` owns the current host-specific package set, Herdr
cgroup policy, and out-of-store `/srv/nori` links. No Home Manager config remains
under `infra/workstation`.

### Roles and inventory

| Old | New |
|---|---|
| `inventory/roles.nix` | `inventory/host-roles.nix` (the `workhorse/appliance/agent/client` placement vocabulary is not access policy) |
| endpoint audience literals | `roles/audiences.nix`, imported by the inventory compiler |
| `inventory/{hosts,workloads,datasets,backup,site}.nix` | unchanged paths; imports and path-valued fields are repaired |

`roles/audiences.nix` owns the allowed `public`, `family`, and `operator`
vocabulary. The route schema derives its allowed audiences from these keys so
the access vocabulary has one authority.

Audience labels are policy inputs, not an authorization-enforcement engine.
Enforcement remains in route, Authelia/OIDC, service-native account, firewall,
and network configurations. A future portal must derive guidance from those
contracts when it is built; a presentation value cannot grant runtime access.

In `inventory/hosts.nix`, change only path-bearing fields:

```text
workstation.managementRoot  nix/hosts/workstation -> infra/workstation
workstation.systemModule    ../nix/hosts/workstation -> ../infra/workstation
workstation.homeModule      ../nix/hosts/workstation/home.nix -> ../users/nori/home.nix
workstation.additionalSourceRoots -> removed (all host files share one root)
pi.managementRoot           pi -> infra/pi
```

`inventory/workloads.nix` imports every moved manifest from `services/**`.
Workload keys, manifests, endpoints, active flags, and host roles do not change.

### Pi backend and every Ansible role

| Old | New |
|---|---|
| `pi/AGENTS.md` | `infra/pi/AGENTS.md` |
| `pi/{ansible.cfg,devenv.lock,devenv.nix,devenv.yaml,requirements.yml,secretspec.toml,pi.just}` | `infra/pi/{ansible.cfg,devenv.lock,devenv.nix,devenv.yaml,requirements.yml,secretspec.toml,pi.just}` |
| `pi/inventory/**` | `infra/pi/inventory/**` |
| `pi/playbooks/**` | `infra/pi/playbooks/**` |
| `pi/scripts/**` | `infra/pi/scripts/**` |
| `pi/tests/vm/**` | `infra/pi/tests/vm/**` |
| `pi/manifest.nix` | `services/pihole/manifest.nix` |
| `pi/roles/base/**` | `infra/common/ansible/roles/base/**` |
| `pi/roles/podman/**` | `infra/common/ansible/roles/podman/**` |
| `pi/roles/firewall/**` | `infra/pi/ansible/roles/firewall/**` |
| `pi/roles/authelia/**` | `services/authelia/ansible/**` |
| `pi/roles/backup/**` | `services/restic-backup/ansible/**` |
| `pi/roles/beszel/**` | `services/beszel/ansible/hub/**` |
| `pi/roles/beszel_agent/**` | `services/beszel/ansible/agent/**` |
| `pi/roles/caddy/**` | `services/caddy/ansible/**` |
| `pi/roles/ddns/**` | `services/cloudflare-ddns/ansible/**` |
| `pi/roles/gatus/**` | `services/gatus/ansible/**` |
| `pi/roles/heartbeat/**` | `services/heartbeat/ansible/**` |
| `pi/roles/ntfy/**` | `services/ntfy/ansible/**` |
| `pi/roles/pihole/**` | `services/pihole/ansible/**` |
| `pi/roles/tailscale/**` | `services/tailscale/ansible/**` |
| `pi/roles/vector/**` | `services/vector/ansible/**` |
| `pi/roles/victorialogs/**` | `services/victorialogs/ansible/**` |
| `pi/roles/victoriametrics/**` | `services/victoriametrics/ansible/**` |

Ansible uses no wrapper roles. `infra/pi/ansible.cfg` supplies explicit search
roots for `infra/common/ansible/roles`, `infra/pi/ansible/roles`, and the
repository `services` root; the playbook names nested service realizations (for
example `caddy/ansible` and `beszel/ansible/agent`). Role order remains byte-for-
byte equivalent to the old playbook order. Test scripts stay with their moved
Ansible realization; Pi VM lifecycle/generator tests stay in `infra/pi/tests`.

The root `Justfile` changes `mod pi 'pi/pi.just'` to
`mod pi 'infra/pi/pi.just'`; all commands remain `just pi::<recipe>`.

### Roots retained or retired

`infra/cloudflare/**`, `products/status/**`, `secrets/**`, root `scripts/**`,
and root cross-component `tests/**` retain their ownership. Test imports are
updated to final paths. `docs/generated/**` remains the generated projection
root.

The tracked `domain/**` realization prototype and its flake/test exposure are
removed. Untracked/ignored prototype roots named `compiler/`, `generated/`,
`implementations/`, `model/`, `modules/`, and `realizations/` are not migrated
or referenced. They are not part of the target architecture.

## Import, scanner, and root-relative hazards

These repairs are part of the migration, not documentation cleanup:

1. `flake.nix` imports every flake-parts module from `lib/flake-parts/**`.
   Every moved flake-parts module has a changed `../../..` depth; package/check
   paths must be resolved from the new file, not search-replaced blindly.
2. `lib/machines.nix`, `inventory/{default,hosts,workloads}.nix`, and
   `profiles/default.nix` form the evaluation spine. Repair these together.
   Preserve the NixOS-vs-Ansible rejection assertions and runtime-module
   deduplication.
3. All manifest `runtimeModule` values change paths. The eight acquisition
   manifests must still name one shared profile module. Public projections
   intentionally remove `runtimeModule`; do not use that omission to skip
   runtime placement checks.
4. Moved Nix files contain relative `import`, `builtins.readFile`, and asset
   paths. High-risk examples are Grafana's dashboard directory, recyclarr YAML,
   agent SOUL/config files, desktop scripts/QML/test fixtures, and papers-fetch
   Python. Their closure must point at the moved artifact.
5. `inputs.self + "/secrets/..."` references remain root-absolute and must not
   be converted to fragile relative paths. `.sops.yaml`, both SecretSpec files,
   and secret keys/names remain unchanged.
6. `infra/pi/scripts/run-production.sh`, `test-vm.sh`, `vm-lifecycle.sh`, and
   generator tests compute the repository root from `BASH_SOURCE`; moving one
   level deeper changes that depth. All `$repo_root/pi/...` paths become
   `$repo_root/infra/pi/...`.
7. `infra/pi/ansible.cfg`, `devenv.nix`, watch paths, shellcheck lists,
   playbook paths, test inventory defaults, and role lookup all depend on the
   former Pi working directory. Verify commands from repository root through
   `just pi::*`, not by assuming an interactive cwd.
8. `Justfile` imports four moved `.just` fragments and the Pi module. Preserve
   recipe names, especially deployment commands embedded as strings in
   inventory.
9. `lint/rules.toml` scopes and exclusions currently target `nix/` and
   `nix/hosts/`. Expand them to the exact final authoritative roots rather than
   weakening the rules. `lint/checks/path-coherence.sh` must recognize `lib`,
   `profiles`, `roles`, and `users`, and its scoped guide list must drop
   `nix/AGENTS.md`/`pi/AGENTS.md` for the new guides.
10. `lint/checks/routing-coherence.sh`, `.githooks/pre-commit`, the OMP
    post-edit hook, `.github/workflows/check.yml`, `.claude/skills/**`, root
    `AGENTS.md`/`CLAUDE.md`, active docs, and runbooks contain routing or scanner
    assumptions. Historical `docs/archive/**` stays historically accurate and
    is excluded from live path rewriting.
11. `scripts/deployment-plan.sh` and `tests/deployment-plan_test.sh` exercise
    source-root matching, moves, unusual filenames, and cross-host ownership.
    Update fixtures to final service and Pi roots; do not reduce those cases.
12. Nix checks directly import old common/service paths. Especially update
    `tests/eval/{architecture-baseline,cloudflare-ddns-routes,deployment,
    gatus-probes,lanroute-*,route-invariants,system-profile-adapters}.nix` and
    `tests/e2e-{alerts-channel-auth,disk-alert,multi-host,pi-smoke,
    restic-backup}.nix`.
13. The convention scanner in `lib/flake-parts/checks/conventions.nix` walks
    service roots and has hard-coded non-service exceptions. Its final scan
    root is only `services/`; exceptions must match the new acquisition and
    split-service shapes without exempting real runtimes.
14. Generated docs packages in `lib/flake-parts/packages/**` and active docs
    cite canonical paths. Regenerate through the existing packages; never edit
    generated projections as a substitute for changing their source.

## Mutually exclusive writer partitions

After one owner performs all `git mv` operations, semantic repair can proceed
in parallel with these non-overlapping write sets:

| Lane | Exclusive write ownership | Acceptance focus |
|---|---|---|
| Nix/service | `services/**` excluding `**/ansible/**`; `inventory/workloads.nix` | manifests, NixOS imports/assets, unchanged enablement/routes/backups |
| Pi/Ansible | `infra/pi/**`, `infra/common/ansible/**`, `services/**/ansible/**` | role lookup/order, generator, check mode, VM harness |
| User/profile/common | `users/**`, `profiles/**`, `roles/**`, `infra/common/nixos/**`, `infra/workstation/**`, `inventory/{hosts,default,host-roles}.nix`, `lib/{machines,nixdoc}.nix` | composition, identity, access policy, host assembly |
| Flake/tests/docs | `flake.nix`, `lib/flake-parts/**`, `tests/**`, `lint/**`, `scripts/**`, `.githooks/**`, `.github/**`, `.claude/**`, root guides/Justfile, active `docs/**` | scanners, evaluation registration, parity and routing |

The integrating lead owns conflict resolution, deletion of empty legacy roots,
and exact-head verification. No lane edits another lane's file to make its own
check green; it reports the needed interface change to that owner.

## Parity evidence and acceptance gates

Before moving files, evaluate and retain machine-readable baselines from the
frozen source for:

- `.#lib.noriInventory`, with only path-valued/private `runtimeModule` fields
  excluded;
- `.#lib.noriDeployment`, comparing all target/order/command values while
  allowing only `sourceRoots` and `machineRoots` keys to rename;
- workstation service enablement and listen ports;
- `nori.lanRoutes`, `nori.backups`, backup targets/delivery, `nori.harden`,
  firewall ports, systemd service/timer names, and filesystem declarations;
- Home Manager state version, selected package names, managed file keys,
  systemd user service/timer names, and agent/desktop option values;
- generated Pi inventory after normalizing only its temporary output filename.

The existing `tests/eval/architecture-baseline.nix` is the primary behavioral
projection and must retain all workload, route, lifecycle, Home Manager, cache,
and runtime placement assertions. Update paths only. Likewise,
`system-profile-adapters.nix`, route/DNS/Gatus checks, deployment projection,
and Pi generator contracts retain their expected values.

Run gates in this order, with at most one heavy job at a time:

1. `nix fmt` and `git diff --check`.
2. `just check-migration` and confirm `rg --files nix pi` returns no files.
3. `just check`.
4. `just pi::check`.
5. Compare the saved before/after semantic projections; differences must be
   limited to the path exclusions above.
6. `just build` (heavy).
7. Relevant NixOS journeys: `just check-vm multi-host`, `pi-smoke`,
   `restic-backup`, `disk-alert`, and music-ingest, using the exact check names
   exposed by `just check-vm` (heavy, serialized).
8. `just pi::test` for convergence, repeat convergence, recovery, and reboot
   evidence (heavy).
9. Regenerate docs and require `docs-fresh`/flake checks to see no stale
   projection.
10. Final exact-head `git status`, `git diff --check`, `just check-migration`,
    `just check`, and both host build/deployment-plan projections.

No live activation or Pi deployment is part of structural acceptance.
