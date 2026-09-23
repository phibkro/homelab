# Infrastructure changes

Start with [the shared guide](../../AGENTS.md). Infrastructure owns reusable host
mechanisms and backend assembly; placement and physical facts remain in
`src/inventory/`.

| Change | Canonical source |
|---|---|
| Workstation realization | `src/infra/workstation/` |
| Shared NixOS mechanisms | `src/infra/common/nixos/` |
| Pi assembly, inventory and harness | `src/infra/pi/` |
| Shared Ansible roles | `src/infra/common/ansible/roles/` |
| Host placement and datasets | `src/inventory/` |

Keep service manifests and backend implementations under `src/services/<name>/`.
Use the existing module, deployment and runtime-test procedures. Do not infer a
live deployment from source configuration; production activation and deployment
remain explicit effects.
