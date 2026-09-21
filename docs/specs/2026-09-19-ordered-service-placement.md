---
summary: Resolve service-owned ordered host selectors into explicit topology realizations.
date: 2026-09-19
status: frozen; implementation authorized; no host activation authorized
owner: operator
---

# Ordered service placement and realizations

## Goal

A service declares where it can run without copying placement into host or profile declarations.

The inventory compiler resolves the declaration deterministically. It emits concrete realization instances before NixOS module selection, deployment planning, topology validation, or generated documentation.

This milestone preserves every current workload-to-host placement. It does not install Adelie, move a service, move a disk, or activate a host.

## User journey

1. Open one service manifest.
2. Read its ordered placement selectors and cardinality.
3. Change a selector or a host tag.
4. Evaluate the inventory.
5. See the selected host or a precise evaluation failure.
6. Inspect the normalized topology and see one realization node for each selected workload and host.
7. Run the deployment planner and see the same affected hosts as before this migration.

No service moves because a profile was added to a host. Profiles no longer own workload placement.

## Authority

The authoritative inputs are:

- `inventory/hosts.nix` for host identity, role, tags, capabilities, profiles, and backend ownership;
- `services/*/manifest.nix` for workload facts, ordered placement selectors, endpoints, and topology requirements;
- `profiles/default.nix` for reusable NixOS system-module composition only.

The compiler derives:

- workload realizations;
- host-to-workload and workload-to-host indexes;
- endpoint host bindings;
- runtime-module selection;
- deployment source ownership;
- normalized topology relationships;
- public inventory views.

Host and profile workload arrays are removed. No compatibility aliases remain.

## Placement declaration

Every workload declares:

```nix
placement = {
  strategy = "first-unique";
  selectors = [
    { tags = [ "nas" ]; }
    { host = "workstation"; }
  ];
  cardinality = {
    min = 1;
    max = 1;
  };
};
```

A selector has exactly one of these shapes:

```nix
{ host = "adelie"; }
{ tags = [ "nas" "nixos" ]; }
{ roles = [ "workhorse" "appliance" ]; }
```

Tag matching uses all declared tags. Role matching uses any declared role because each host has one role.

Host names and tags have separate fields. A host named `nas` does not collide with the tag `nas`.

## Resolution

`first-unique` evaluates selectors in order:

1. Match the selector against the host inventory.
2. Continue when it matches no hosts.
3. Select the host when it matches exactly one host.
4. Fail when it matches more than one host.
5. Fail when every selector is empty.

`all-matches` unions every selector result and sorts host names. It fails when the result violates cardinality.

All selected hosts must satisfy the workload's existing `hostRoles` declaration. Capability requirements continue to validate the selected host after resolution.

This milestone does not score hosts, inspect runtime load, or reschedule services. Resource optimization requires declared resource requests and a separate frozen contract.

## Realization identity

The normalized graph uses stable realization nodes:

```text
realization.<workload>.primary
realization.<workload>.<host>
```

`first-unique` creates the `primary` realization. `all-matches` creates one host-named realization per selected host.

A realization has JSON-safe properties:

```nix
{
  workload = "jellyfin";
  host = "adelie";
}
```

Relationships are explicit:

```text
realization --Realizes--> workload
realization --HostedOn--> host
endpoint    --ProvidedBy--> workload
endpoint    --BoundTo--> realization
```

An endpoint is valid only when its workload has exactly one realization in this milestone. Current multi-host agents expose no endpoint, so current behavior is preserved without choosing an arbitrary instance.

A requirement with `target = null` belongs to each realization and targets that realization's host. An explicit target keeps its declared stable topology node ID.

The topology schema version advances because realization nodes and relationships change the public graph contract.

## Current aliases

Host tags initially preserve current behavior:

- `entry-plane` selects Pi;
- `primary-service-host` selects workstation;
- `nas` identifies Adelie for later migrations;
- `nixos` selects Adelie and workstation;
- `large-gpu` identifies workstation;
- `gpu-host` identifies Adelie.

Adding `nas` does not move a current service. A later service migration changes its ordered selector under a separate operator-gated specification.

## Failure behavior

Inventory evaluation fails when:

- a workload has no placement declaration;
- placement has unknown fields;
- a selector has zero or multiple selector kinds;
- a selector names an unknown host, tag, or role;
- `first-unique` encounters an ambiguous non-empty selector;
- `all-matches` violates cardinality;
- cardinality is malformed;
- a selected host violates `hostRoles`;
- an endpoint belongs to a workload with zero or multiple realizations;
- a requirement cannot resolve against its realization host.

A stateful relocation is not part of this milestone. Future deployment work must classify a changed realization host as a migration effect rather than an ordinary switch.

## Runtime behavior

The resolved host sets must remain identical to the baseline:

- Adelie runs `beszel-agent` and `node-exporter`.
- Pi keeps its entry-plane workloads plus `beszel-agent` and `ntfy-notify`.
- Workstation keeps its current family, media, operator, research, backup, and per-host agents.

Generated routes, NixOS runtime modules, deployment targets, source-root ownership, and activation order remain behaviorally unchanged.

## Acceptance

The implementation is complete when:

1. Every catalog workload has one valid placement declaration.
2. Host and profile declarations contain no workload placement arrays.
3. No endpoint manifest contains `runsOn`.
4. Public host and workload projections preserve their current resolved host sets.
5. The normalized graph contains deterministic realization nodes and realization relationships.
6. A tag selector, an exact-host selector, and a role selector resolve in positive fixtures.
7. Unknown selector fields, unknown names, ambiguous `first-unique`, invalid cardinality, and role violations fail for their intended reasons.
8. The canonical JSON projection contains the revised graph without becoming an authoring source.
9. Deployment selector and changed-path behavior remains unchanged.
10. Fast repository checks and both NixOS host builds pass from committed source.

## Rejected alternatives

### Bare strings

Rejected because a string could ambiguously name a host, role, or tag.

### Profile-owned workloads

Rejected because adding a reusable machine profile can silently add unrelated services.

### Runtime scheduler

Rejected because transient runtime state is not desired-state authority. This homelab needs deterministic planning and explicit activation, not autonomous movement.

### Hand-authored realization map

Rejected because it duplicates service placement policy. Realizations are a pure compiler output.

## Change control

This contract is frozen for this implementation. Semantic changes require an explicit edit before code changes. Host activation, service relocation, disk movement, runtime scoring, failover, and resource balancing remain outside this milestone.
