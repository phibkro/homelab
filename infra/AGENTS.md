# Infrastructure changes

Start with [the shared guide](../AGENTS.md). Infrastructure owns reusable host
mechanisms and backend assembly; placement and physical facts remain in
`inventory/`.

| Change | Canonical source |
|---|---|
| Workstation realization | `infra/workstation/` |
| Shared NixOS mechanisms | `infra/common/nixos/` |
| Pi assembly, inventory and harness | `infra/pi/` |
| Shared Ansible roles | `infra/common/ansible/roles/` |
| Host placement and datasets | `inventory/` |

Keep service manifests and backend implementations under `services/<name>/`.
Use the existing module, deployment and runtime-test procedures. Do not infer a
live deployment from source configuration; production activation and deployment
remain explicit effects.
