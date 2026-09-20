---
summary: Inventory-derived build and activation planning, change scoping, order,
  safety boundaries, and the operator review/activation handoff.
---

# Deployment

The repository provides a read-only deployment planner. It derives targets,
backend-specific commands, Nix build attributes, and backend-before-entry-plane
ordering from the same pure inventory that creates NixOS outputs and the Pi's
Ansible inventory. It does not SSH, switch, mutate DNS, or activate a host.

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
particular, `infra/pi/**` selects the Pi's Ansible commands and cannot produce a Nix
build. An unknown configuration path conservatively selects all hosts;
documentation and tests select no activation targets.

## Command effects

`just` displays help. `just check` runs fast Nix checks; `just pi::check` checks
Ansible. `just check-vm [name]` and `just pi::test` exercise disposable machines.
`just check-all` selects every check through the same metadata dispatcher as
`just check`. `just build` builds without activation.
`just activate-test` changes the live system for the current boot; `rebuild`,
`boot`, `deploy`, `push`, and remote activation commands also have live effects.
Ansible `pi::plan` uses production credentials and contacts the real appliance.

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
4. run `just pi::deploy` last when entry-plane configuration is selected;
5. run internal route/runtime checks and an off-LAN acceptance check;
6. clear maintenance or roll back the affected host generation.

The planner intentionally stops before these steps. A future deployment wrapper
may automate the sequence only if it preserves the explicit operator gate,
maintenance state, acceptance checks, and per-host rollback.

Backup scheduling remains disabled during the source migration. Before later
enabling it, follow the mount, capacity, SSH identity,
SFTP isolation, and restore gates in the
[OneTouch cutover runbook](../runbooks/onetouch-backup-cutover.md). Workstation must
serve the verified destination before Pi switches to it.

## Verification contract

`just check` verifies that NixOS inventory hosts—and only those hosts—have
Nix build targets, the Ansible Pi has exact operator commands, workload roots
scope to their actual hosts, and the entry plane follows backends. The
deployment-plan package test also proves that selecting Pi emits no Nix build,
exercises semantic change detection in a temporary Git repository, and runs
ShellCheck on the planner.

These are check contracts, not a record that a particular revision passed.
Nix entry-plane adapter tests exercise the Nix implementation and shared
contracts; they do not verify the Ansible production runtime. Run
`just pi::check` and `just pi::test` for Ansible evidence, then verify the live
Pi after approved activation. A disposable convergence test cannot establish
production credentials, physical disk capacity, or backup restorability.
