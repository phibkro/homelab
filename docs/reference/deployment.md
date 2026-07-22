---
summary: Inventory-derived build and activation planning, change scoping, order,
  safety boundaries, and the operator review/activation handoff.
---

# Deployment

The repository provides a read-only deployment planner. It derives targets,
build attributes, and backend-before-entry-plane ordering from the same pure
inventory that creates NixOS and Home Manager outputs. It does not SSH, switch,
mutate DNS, or activate a host.

## Plan a change

```bash
# Scope committed, staged, and working-tree changes against a base
just plan-deploy origin/main

# Select explicitly; selectors may be combined
nix run .#deployment-plan -- --host aurora
nix run .#deployment-plan -- --profile media-compute
nix run .#deployment-plan -- --workload jellyfin
nix run .#deployment-plan -- --all
```

The JSON result contains `hosts`, the reasons they were selected, exact flake
`builds`, and `activationOrder`. Known inventory, workload, profile, and machine
roots narrow the plan. An unknown configuration path conservatively selects all
hosts; documentation and tests select no activation targets.

## Build before activation

Build every attribute in the plan before touching a live host:

```bash
nix build \
  .#nixosConfigurations.aurora.config.system.build.toplevel \
  .#nixosConfigurations.workstation.config.system.build.toplevel
```

`macbook` is part of the unified host inventory but has a Home Manager build
target, `.#homeConfigurations.macbook.activationPackage`, and never appears in
the NixOS activation order.

## Activation boundary

Production activation remains an operator action after branch/PR review. For a
multi-host change:

1. announce or enter maintenance when user-facing availability may change;
2. build all selected closures;
3. activate selected backend hosts in the plan's order;
4. activate `pi` last when entry-plane configuration is selected;
5. run internal route/runtime checks and an off-LAN acceptance check;
6. clear maintenance or roll back the affected host generation.

The planner intentionally stops before these steps. A future deployment wrapper
may automate the sequence only if it preserves the explicit operator gate,
maintenance state, acceptance checks, and per-host rollback.

## Verification contract

`nix flake check` verifies that every inventory host has a build target, workload
roots scope to their actual hosts, and the entry plane follows backends. The
deployment-plan package test also exercises semantic change detection in a
temporary Git repository and runs ShellCheck on the planner.
