---
summary: Inventory-derived build and activation planning, change scoping, order,
  safety boundaries, and the operator review/activation handoff.
---

# Deployment

The repository provides a read-only deployment planner. It derives targets,
backend-specific commands, Nix build attributes, and backend-before-entry-plane
ordering from the pure inventory. It creates NixOS outputs and Pi Ansible
plans. Pi runs Debian. Ansible provisions its Podman services. Pi has no NixOS
configuration. The planner does not SSH, switch, mutate DNS, or activate a
host.

## Plan a change

```bash
# Scope committed, staged, and working-tree changes against a base
just plan-deploy origin/main

# Select explicitly; selectors may be combined
nix run .#deployment-plan -- --host workstation
nix run .#deployment-plan -- --profile media-compute
nix run .#deployment-plan -- --workload jellyfin
nix run .#deployment-plan -- --all
```

The JSON result contains `hosts`, the reasons they were selected, exact Nix
`builds`, Ansible `plans`/`applies`/`verifies`, and `activationOrder`. Known
inventory, workload, profile, and management roots narrow the plan. In
particular, `src/infra/pi/**` selects the Pi's Ansible commands and cannot produce a Nix
build. An unknown configuration path conservatively selects all hosts;
documentation and tests select no activation targets.

## Command effects

Each deployment owner has one activation command:

| Target | Activation command |
|---|---|
| Workstation | `just rebuild` |
| Adelie | `just push adelie` |
| Pi | `PI_DEPLOY_CONFIRM="pi@$pi_target" just pi::deploy` |

`just` displays help. `just check` runs fast Nix checks; `just pi::check` checks
Ansible. `just check-vm [name]` and `just pi::test` exercise disposable machines.
`just check-all` selects every check through the same metadata dispatcher as
`just check`. `just build` builds without activation.
`just activate-test` changes the live system for the current boot. `rebuild`,
`boot`, `deploy`, `push`, and `pi::deploy` have live effects. Ansible `pi::plan`
uses production credentials and contacts the real appliance.

For Pi activation, derive the reviewed target from the same inventory source
used by the production runner:

```bash
pi_target="$(nix eval --raw .#lib.noriInventory.hosts.pi.lanIp)"
PI_DEPLOY_CONFIRM="pi@$pi_target" just pi::deploy
```

The runner independently derives the target and rejects a different
confirmation value.

## Build before activation

Build every attribute in the plan before touching a live host:

```bash
nix build \
  .#nixosConfigurations.workstation.config.system.build.toplevel
```

Only `kind = "nixos"` targets build a `toplevel`. The Pi is
`kind = "ansible"`, has no `nixosConfigurations.pi`, and is checked through its
declared plan command:

```bash
just pi::plan
```

## Activation boundary

Production activation requires applicable operator authorization after reviewing
the prepared change and evidence. Existing authorization in the session carries
forward; do not add another approval gate when it already covers the action. For a
multi-host change:

1. announce or enter maintenance when user-facing availability may change;
2. build all selected Nix closures and run selected Ansible plan commands;
3. activate selected NixOS backend hosts in the plan's order;
4. deploy Pi last with the inventory-derived `PI_DEPLOY_CONFIRM` value when entry-plane configuration is selected;
5. run internal route/runtime checks and an off-LAN acceptance check;
6. clear maintenance or roll back the affected host generation.

The planner intentionally stops before activation. This keeps the operator
gate, maintenance state, acceptance checks, and per-host rollback explicit.

The OneTouch backup policy is enabled in `src/inventory/backup.nix`. Pi and Adelie
use restricted accounts on the workstation-attached destination. September 19
evidence covers Pi transport, eight fresh snapshots, eight metadata checks, and
a Pi-hole configuration restore. Physical reboot, off-LAN behavior,
application/database recovery, user-data/media recovery, and full data-block
integrity remain operator-gated. Read the
[OneTouch cutover runbook](../runbooks/onetouch-backup-cutover.md) before an
activation.

Use the normal deployment recipes for changes that can interrupt a public
family service. Gatus does not add or close maintenance events.

The public Gatus instance shows current health for Jellyfin, Navidrome, and
Seerr. It runs on Pi and uses the inventory `publicStatus` grants. Pi Caddy
publishes the instance at `status.home.phibkro.org`. The route-derived DDNS
record stays DNS-only.

This Gatus instance probes from Pi. Therefore, its results do not prove off-LAN
access. Use the ADR-0006 cellular-data procedure to make sure that the public
path works. The [September 21 Gatus acceptance report](../archive/reports/2026-09-21-public-gatus-acceptance.md)
records the source cutover, deployed boundary, and live results.

The earlier [Worker acceptance](../archive/reports/2026-09-21-public-status-acceptance.md)
is historical evidence for the retired Worker and D1 implementation.

## Verification contract

`just check` verifies that NixOS inventory hosts—and only those hosts—have
Nix build targets, the Ansible Pi has exact operator commands, workload roots
scope to their actual hosts, and the entry plane follows backends. The
deployment-plan package test also proves that selecting Pi emits no Nix build,
exercises semantic change detection in a temporary Git repository, and runs
ShellCheck on the planner.

These are check contracts, not a record that a particular revision passed.
Disposable Nix adapter tests exercise shared Nix modules. They do not verify
the Pi Debian/Ansible/Podman runtime. Run `just pi::check` and `just pi::test`
for Ansible evidence, then verify the live Pi after approved
activation. A disposable convergence test cannot establish production
credentials, physical disk capacity, or backup restorability.
