---
summary: Three deployment owners, shared inventory, and failure domains.
---

# Topology

`inventory/hosts.nix` owns host identity, explicit profiles, and placement
tags. Service manifests own ordered placement selectors. Use the
[generated topology](../generated/topology.md) for the derived host catalog.

| Target | Runtime owner | Responsibility |
|---|---|---|
| adelie | NixOS | SSD-local application backends and fleet agents |
| workstation | NixOS + Home Manager | Desktop, GPU and media workloads, hot SSD storage, and attached IronWolf Pro and OneTouch disks |
| pi | Debian appliance; Ansible provisions Podman services under `infra/pi/` | HTTP entry plane, DNS, Glance, monitoring, alerts, subnet routing, exit-node services, and appliance backups |

Ansible is the only live deployment owner for Pi. The verified NixOS image is
an offline rollback artifact. Aurora and Pavilion are retired. They do not
provide backup, deployment, or topology roles.

## Failure domains

```text
clients → Pi entry plane → Adelie or workstation application backends
Pi appliance backups → restricted SFTP → workstation-attached OneTouch
Adelie backups → restricted SFTP → workstation-attached OneTouch
workstation backups → OneTouch (policy: inventory/backup.nix)
```

The inventory enables the OneTouch backup policy. Pi and Adelie use restricted
accounts on the workstation-attached destination. The roadmap records Pi backup
transport, eight fresh snapshots, eight metadata checks, and a Pi-hole
configuration restore. Physical reboot, off-LAN behavior, recovery, and
data-integrity gates remain operator-gated.

Keeping the entry plane on Pi preserves monitoring and network functions during
a workstation outage. Local snapshots share their source disk's failure domain.
OneTouch provides a separate disk, but an attached workstation backup still
shares its power and administrative failure domain. No off-site copy is
provided by this plan.

## Ownership and cross-host configuration

The inventory compiler resolves service-owned selectors against host identity,
roles, and tags. It emits explicit workload realization nodes before producing
NixOS or Ansible projections. NixOS modules receive host identity through
`config.nori.inventory.hosts`.
Workstation and Adelie modules implement NixOS behavior. Pi runs Debian.
Ansible provisions its Podman services. A shared manifest or a Nix adapter test
does not prove that the Pi appliance converges correctly.

Profiles select reusable system modules. They do not own workloads. Endpoints
bind to one realization; replicated agent workloads do not expose endpoints.

See [module authoring](module-authoring.md) for composition rules,
[deployment](deployment.md) for activation order, and
[storage](storage.md) for the backup contract. Introducing another managed host
requires an explicit inventory entry, runtime owner, deployment commands, and
failure-domain rationale. Secret enrollment is a separate operator action.
