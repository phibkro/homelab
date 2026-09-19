---
summary: Two deployment owners, shared inventory, and failure domains.
---

# Topology

`inventory/hosts.nix` owns host identity, explicit profiles, and placement
tags. Service manifests own ordered placement selectors. Use the
[generated topology](../generated/topology.md) for the derived host catalog.

| Target | Runtime owner | Responsibility |
|---|---|---|
| adelie | NixOS | Staged storage and media host; currently realizes fleet agents only |
| workstation | NixOS + Home Manager | Desktop, application backends, hot SSD storage and cold IronWolf Pro storage |
| pi | Ansible under `infra/pi/` | HTTP entry plane, DNS, monitoring, alerts, subnet routing and exit-node services |

Aurora and Pavilion are outside the main deployment inventory. Aurora may
serve as a temporary backup endpoint if independently verified reachable;
historical attachment records do not establish its current disks or coverage.

## Failure domains

```text
clients → Pi entry plane → workstation or Adelie application backends
backup destination → OneTouch (policy: inventory/backup.nix)
```

Keeping the entry plane on Pi preserves monitoring and network functions during
a workstation outage. Local snapshots share their source disk's failure domain.
OneTouch provides a separate disk, but an attached workstation backup still shares its power
and administrative failure domain. No off-site copy is provided by this plan.

## Ownership and cross-host configuration

The inventory compiler resolves service-owned selectors against host identity,
roles, and tags. It emits explicit workload realization nodes before producing
NixOS or Ansible projections. Workstation and Adelie modules implement NixOS
behavior; Pi roles implement Ansible behavior. A shared manifest or tested Nix
adapter is not evidence that the corresponding Pi role converges correctly.

Profiles select reusable system modules. They do not own workloads. Endpoints
bind to one realization; replicated agent workloads do not expose endpoints.

See [module authoring](module-authoring.md) for composition rules,
[deployment](deployment.md) for activation order, and
[storage](storage.md) for the backup contract. Introducing another managed host
requires an explicit inventory entry, runtime owner, deployment commands, and
failure-domain rationale. Secret enrollment is a separate operator action.
