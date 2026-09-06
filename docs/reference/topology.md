---
summary: Two deployment owners, shared inventory, and failure domains.
---

# Topology

`inventory/hosts.nix` owns host identity, explicit profiles, and intended
placement. Use the [generated topology](../generated/topology.md) for the host
catalog and hardware details; change inventory rather than duplicating it here.

| Target | Runtime owner | Responsibility |
|---|---|---|
| workstation | NixOS + Home Manager | Desktop, application backends, hot SSD storage and cold IronWolf Pro storage |
| pi | Ansible under `infra/pi/` | HTTP entry plane, DNS, monitoring, alerts, subnet routing and exit-node services |

Aurora and Pavilion are outside the main deployment inventory. Aurora may
serve as a temporary backup endpoint if independently verified reachable; its
existing OneTouch connection is not evidence of current backup coverage.

## Failure domains

```text
clients → Pi entry plane → workstation application backends
planned backups → OneTouch (disabled pending connection)
```

Keeping the entry plane on Pi preserves monitoring and network functions during
a workstation outage. Backup delivery is currently disabled; local snapshots
share their source disk's failure domain. Once connected, OneTouch provides
a separate disk, but an attached workstation backup still shares its power
and administrative failure domain. No off-site copy is provided by this plan.

## Ownership and cross-host configuration

The inventory compiler supplies placement and public connection facts to both
runtimes. Workstation modules implement NixOS behavior; Pi roles implement
Ansible behavior. A shared manifest or tested Nix adapter is not evidence that
the corresponding Pi role converges correctly.

Clients such as exporters and log shippers remain local to their source host;
servers and entry routes follow explicit inventory placement. Do not infer
placement from tags or import every workload runtime to discover metadata.

See [module authoring](module-authoring.md) for composition rules,
[deployment](deployment.md) for activation order, and
[storage](storage.md) for the backup contract. Introducing another managed host
requires an explicit inventory entry, runtime owner, deployment commands, and
failure-domain rationale. Secret enrollment is a separate operator action.
