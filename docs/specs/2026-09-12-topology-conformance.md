---
date: 2026-09-12
status: implemented
seed: operator approval after architecture review
summary: Compile the existing Nix inventory into one normalized topology graph and validate capability and policy requirements without creating a second source of truth.
---

# Topology conformance

## Goal

Make architectural contradictions fail during Nix evaluation.

The existing Nix inventory remains the authoritative desired-system model. The compiler normalizes that model once. Validation, documentation, deployment projections, and later runtime comparisons consume the normalized graph.

The first milestone covers one complete path:

```text
host capability declarations
        +
workload requirement declarations
        |
        v
normalized topology graph
        |
        `--> semantic conformance checks
```

Ollama is the compute pilot. Vaultwarden is the stateful and identity pilot.

## User journeys

### Valid change

1. The operator changes a host capability or workload requirement.
2. `nix eval .#lib.noriInventory.topology` returns the normalized graph.
3. `nix build .#topology-intent-json` creates its canonical JSON projection.
4. The topology checks pass because all mandatory requirements resolve.

### Invalid change

1. The operator removes CUDA from the host that runs Ollama.
2. Inventory evaluation fails before a host build or activation.
3. The error names the workload, requirement, target, and failed constraint.

The same rule applies to a missing Vaultwarden storage or identity provider.

## Correctness boundary

```text
AUTHORITATIVE                         DERIVED

inventory/hosts.nix       --------+
profiles/default.nix      --------+ |
services/*/manifest.nix   --------|-+--> normalized graph
inventory/datasets.nix    --------+          |
inventory/disks.nix       --------+          +--> JSON
inventory/backup.nix      --------+          +--> human views
policies and audiences    --------+          `--> realization comparison
```

Do not parse Nix source text to infer topology. Evaluate the source and export the selected values.

Do not edit generated JSON or human views. They are disposable projections.

## Terms

| Term | Meaning |
|---|---|
| Principal | An identity that can receive authority. A user or workload can be a principal. |
| Machine | A physical or virtual compute boundary. |
| Device | A movable hardware resource with its own identity. |
| Workload | A deployable service or process contract. |
| Endpoint | A network interface exposed by a workload. |
| Dataset | A persistent information asset. It is not a disk. |
| Capability | A feature that a node can provide. |
| Requirement | A mandatory capability that another node must provide. |
| Relationship | A directed, typed edge between nodes. |
| Policy | A constraint on placement, access, durability, lifecycle, or observation. |
| Realization | A concrete backend plan or deployed result. |
| Evidence | A timestamped observation with provenance. |

A client is a role, not a node kind. A workload or user acts as a client when it calls a service.

A device is not part of a machine identity. `inventory/disks.nix` records the current attachment separately.

A capability is not an authorization grant. A GPU capability says that computation is possible. It does not grant `/dev/nvidia*` access.

## Normalized graph contract

The public inventory adds `topology` with this shape:

```nix
{
  schemaVersion = 1;

  nodes = [
    {
      id = "host.workstation";
      kind = "machine";
      properties = { ... };
      capabilities = {
        "nori.capabilities.Compute" = {
          architecture = "x86_64";
          cores = 16;
          memoryBytes = 68719476736;
        };
      };
    }
  ];

  requirements = [
    {
      id = "workload.ollama.requirement.accelerator@host.workstation";
      owner = "workload.ollama";
      name = "accelerator";
      capability = "nori.capabilities.GpuCompute";
      relationship = "nori.relationships.Uses";
      target = "host.workstation";
      constraints = {
        backend.equal = "cuda";
        vramBytes.atLeast = 8589934592;
      };
    }
  ];

  relationships = [
    {
      id = "relationship.hosted-on.workload.ollama.host.workstation";
      type = "nori.relationships.HostedOn";
      source = "workload.ollama";
      target = "host.workstation";
      properties = { };
    }
  ];
}
```

### Stable identities

Use these namespaces:

```text
host.<host-name>
device.<device-name>
workload.<workload-name>
endpoint.<workload-name>.<endpoint-name>
dataset.<dataset-name>
```

A node ID must be unique. A relationship ID must be a pure function of its type, source, target, and optional requirement name.

Sort node, requirement, and relationship lists by `id`. Identical source data must produce byte-identical JSON output.

### Node capabilities

`inventory/hosts.nix` can declare:

```nix
capabilities = {
  "nori.capabilities.Compute" = {
    architecture = "x86_64";
    cores = 16;
    memoryBytes = 68719476736;
  };
  "nori.capabilities.GpuCompute" = {
    backend = "cuda";
    vendor = "nvidia";
    vramBytes = 17179869184;
  };
  "nori.capabilities.PersistentStorage" = {
    class = "local";
  };
};
```

A workload or endpoint can provide the same typed capability through its manifest.

The first milestone permits only JSON-safe scalar values in capability properties. Secrets, paths, derivations, and functions remain forbidden from the public graph.

### Workload requirements

A service manifest can declare:

```nix
topology.requires.accelerator = {
  capability = "nori.capabilities.GpuCompute";
  relationship = "nori.relationships.Uses";
  target = null;
  constraints = {
    backend.equal = "cuda";
    vramBytes.atLeast = 8589934592;
  };
};
```

`target = null` means the workload's selected placement host. The compiler expands one requirement for each selected host.

An explicit target uses a stable node ID:

```nix
topology.requires.identity = {
  capability = "nori.capabilities.OidcProvider";
  relationship = "nori.relationships.AuthenticatedBy";
  target = "workload.authelia";
  constraints = { };
};
```

All declared requirements are mandatory. Optional requirements are not part of milestone one. Add optionality only with an observable semantic need.

Supported property constraints are:

| Operator | Input | Meaning |
|---|---|---|
| `equal` | one JSON-safe scalar | Provider value must equal the input. |
| `atLeast` | one integer | Provider integer must be greater than or equal to the input. |
| `oneOf` | non-empty list of scalars | Provider value must be a member of the input list. |

Each property uses exactly one operator. Unknown operators fail evaluation.

## Generated relationships

The compiler creates structural edges from existing inventory data:

| Source data | Relationship |
|---|---|
| Workload placement | `nori.relationships.HostedOn` from workload to host |
| Endpoint ownership | `nori.relationships.ProvidedBy` from endpoint to workload |
| Disk attachment | `nori.relationships.AttachedTo` from device to host |
| Dataset producer | `nori.relationships.Writes` from workload to dataset |
| Dataset consumer | `nori.relationships.Reads` from workload to dataset |
| Declared requirement | The relationship type in the requirement |

The compiler does not infer relationships from comments, paths, ports, tags, or names.

## Conformance rules

Inventory evaluation must fail when:

1. A node ID or relationship ID is duplicated.
2. A relationship source or target does not exist.
3. A mandatory requirement has no target.
4. A requirement target does not provide the named capability.
5. A capability property does not satisfy its constraint.
6. A constraint uses an unknown operator or invalid value type.
7. A workload selects a host outside its declared placement roles.
8. An endpoint has no selected host or selects a host outside its workload placement.
9. A public topology value crosses the existing implementation or secret boundary.

Existing inventory assertions continue to enforce unknown references, disk identity, dataset references, endpoint uniqueness, public exposure, and artifact contracts.

Checks must include a valid baseline and counterexamples. A check that only serializes current production data is not a conformance test.


## State and evidence model

The complete architecture uses five separate artifacts:

| State | Authority | Artifact | Claim |
|---|---|---|---|
| Intended | Nix inventory and contracts | `topology.intent.json` | Desired architecture |
| Planned | Evaluated backend plan | `topology.plan.<target>.json` | Selected realization |
| Active | Deployment identity on a machine | `/etc/nori/topology.json` | Activated generation |
| Observed | Timestamped collectors | `topology.observed.<host>.<time>.json` | Current facts |
| Proven | Real user journey or service check | Existing checks and runbooks | Required behavior worked |

Do not collapse these states into one `current topology` document.

A build proves buildability. It does not prove activation.

An active manifest proves deployment identity. It does not prove that a service is healthy.

An observation proves only the facts that its collector recorded. Unknown or expired evidence stays unknown.

A functional smoke journey proves behavior. It does not prove every topology property.

## First milestone

### Scope

1. Add typed capabilities to the existing three hosts.
2. Add Ollama's CUDA requirement.
3. Add Vaultwarden's compute, persistent-storage, and OIDC requirements.
4. Add Authelia's OIDC-provider capability.
5. Compile all current machines, devices, workloads, endpoints, and datasets into the normalized graph.
6. Validate all declared requirements and graph edges.
7. Export the canonical JSON package.
8. Add semantic counterexamples for an unsatisfied capability, unknown target, and failed numeric constraint.

### Runtime behavior

No service is enabled, disabled, moved, restarted, or reconfigured by this milestone.

Ollama keeps its current active state. Its requirement validates the selected placement before any future activation change.

Vaultwarden and Authelia keep their current placement and runtime configuration.

### Acceptance

Run these journeys:

```bash
nix eval .#lib.noriInventory.topology --json
nix build .#topology-intent-json
nix build .#checks.x86_64-linux.eval-topology-conformance
nix build .#checks.x86_64-linux.eval-inventory-public-safe
```

Then inspect the built artifacts. They must contain:

- `host.workstation` with CUDA and persistent-storage capabilities;
- `workload.ollama` with a resolved GPU requirement to `host.workstation`;
- `workload.vaultwarden` with resolved host storage and Authelia identity requirements;
- no `runtimeModule`, Nix path, derivation, secret key, or secret value.

The negative fixtures must fail for the intended semantic reason. They must not fail because of malformed test scaffolding.

## Later stages

### Stage 2: more capability and policy coverage

Migrate one complete concern at a time:

1. endpoint exposure and access;
2. persistent datasets and writers;
3. backup durability and failure domains;
4. GPU and device authority grants;
5. lifecycle and observability obligations.

Each migration adds a positive production case and a counterexample before the next concern starts.

### Stage 3: realization manifests

Each backend exports what it selected:

- NixOS exports an evaluated realization graph from module options;
- Ansible exports a plan graph from generated role variables;
- Alchemy exports a plan graph from its deployment model.

Compare normalized intent with the selected plan. Do not compare YAML or JSON formatting.

### Stage 4: active deployment identity

Install `/etc/nori/topology.json` with the selected graph digest, source revision, lock digest, host, and generation identity.

Activation updates this file in the same generation as the services that it describes.

### Stage 5: observations

Add a local collector for governed facts only:

- active generation;
- systemd unit state;
- listeners;
- mounts;
- attached device identities;
- selected service versions;
- backup snapshot age;
- collector name, version, and timestamp.

Collectors must not read or emit secret content.

### Stage 6: convergence

Replace duplicated prose and configuration facts with generated projections or references. Keep functional checks separate from topology conformance.

## Repository map

| Existing path | Role after migration |
|---|---|
| `inventory/default.nix` | Normalize the graph and enforce pure cross-resource invariants. |
| `inventory/hosts.nix` | Machine identity, placement intent, and host capabilities. |
| `inventory/disks.nix` | Device identities and current attachment. |
| `inventory/datasets.nix` | Dataset ownership and persistence intent. |
| `inventory/backup.nix` | Durability policy input. |
| `services/*/manifest.nix` | Workload contracts, capabilities, requirements, state, and endpoints. |
| `profiles/default.nix` | Reusable logical compositions. |
| `roles/audiences.nix` | Audience and access-policy vocabulary. |
| `infra/*` | Concrete backend realizations. |
| `lib/flake-parts/packages/inventory.nix` | Public inventory, topology JSON, and deployment-plan outputs. |
| `tests/eval/*` | Semantic counterexamples. |
| `docs/generated/*` | Generated human projections. |

## Rejected alternatives

### TOSCA projection

Rejected because no deployer or operator workflow consumes it. A maintained
second representation and its self-check do not strengthen the normalized
graph. Add an exporter only with a named consumer, schema-version owner, and
release lifecycle.

### Source-code scanning

Rejected because filenames, comments, and option spelling are not evaluated semantics.

### One graph called current state

Rejected because intended, planned, active, observed, and proven claims have different authorities.


### Runtime-only validation

Rejected because placement and policy contradictions can fail earlier during evaluation.

## Change control

This specification is frozen for the first milestone. If implementation finds a semantic contradiction, update this file explicitly before changing the contract.

Later stages can add node kinds, capability types, requirement operators, or evidence fields. They must not weaken these invariants:

- Nix inventory is the single desired-state authority.
- Every derived artifact has an explicit edge to the normalized graph.
- Mandatory requirements never resolve by guessing.
- Runtime evidence never masquerades as desired state.
- Functional verification remains separate from topology conformance.
