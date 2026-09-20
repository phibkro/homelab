---
summary: Compile host, workload, endpoint, and Pi appliance intent once and make every backend consume the resulting projections.
date: 2026-09-20
status: accepted for implementation; production activation remains operator-gated
owner: operator
---

# Inventory projection consolidation

## Goal

`inventory/` is the only authoring source for host identity, workload placement, activation, endpoints, and Pi appliance intent.

The inventory compiler produces typed, secret-free projections for NixOS, Ansible, deployment planning, topology, status, and documentation. No backend independently rebuilds or reinterprets those facts.

## Required behavior

### Canonical routes

Each active HTTP endpoint produces one resolved route record. The record owns its workload, endpoint name, selected host, hostname, port, reachability, audience, authentication, monitoring, and dashboard metadata.

Inactive workloads remain visible in the catalog but produce no active route, runtime module, DNS record, monitor, or Pi role activation.

Pi and NixOS adapters consume the same resolved route projection. They may apply explicit backend address policy, but they must not independently select placement, defaults, or activation.

### Pi projection

The compiler produces the complete secret-free Pi Ansible projection:

- appliance routes;
- local DNS records;
- DDNS hostnames;
- Authelia OIDC clients;
- Gatus probes;
- Glance bookmarks;
- VictoriaMetrics scrape jobs;
- Beszel systems;
- workload enable flags;
- backup target and job metadata.

The Pi inventory generator only adds deployment transport data and serializes this projection. Ansible templates retain runtime rendering and binary validation.

Pi-hole owns its web route, DNS port, and health metadata in its workload manifest. No generator or group variable repeats its ports.

### NixOS projection

`config.nori.inventory.hosts` is the only Nix host registry. All compatibility `config.nori.hosts` readers migrate in one cutover.

NixOS runtimes read ports, activation, and endpoints from `config.nori.inventory`. They do not import their own manifests or repeat endpoint ports.

Pi-only workloads do not retain unused NixOS runtime implementations. A deliberately retained test adapter must be named and documented as test-only.

### Operational records and tooling

`docs/roadmap.md` is the only forward-work queue. Archived plans remain historical evidence and do not carry executable statuses.

Generated-document helpers have one implementation. Service convention checks derive their coverage from the explicit workload catalog. Local and CI check entrypoints use the same check-group dispatcher.

## Safety boundaries

- Keep Pi on Debian and Ansible. This change does not migrate the appliance to NixOS.
- Keep the normalized topology graph, ordered placement, `hostRoles` admission checks, and restricted TOSCA export.
- Keep inactive workload declarations for later reactivation.
- Keep secret values out of public and Pi projections.
- Preserve route names, hostnames, ports, auth policy, monitor behavior, DNS answers, and generated Pi role order during the cutover.
- Do not activate workstation, Adelie, or Pi as part of implementation. Production activation remains a separate operator action.

## Acceptance

1. Public inventory evaluation rejects malformed endpoint and monitor declarations before backend generation.
2. The new Pi projection is semantically equal to the prior generated production inventory for all unchanged services.
3. Pi-hole listener, route, DNS, and monitor ports derive from one manifest declaration.
4. Setting a workload inactive removes its runtime, routes, monitors, and Pi enablement while retaining catalog metadata.
5. No source reader uses `config.nori.hosts` or imports `manifest.nix` to decide runtime activation.
6. No Pi-only production workload advertises a NixOS runtime module.
7. Generated Pi inventory contains no secret value, Nix path, derivation, or runtime module path.
8. Focused inventory, topology, route, Pi contract, and documentation freshness checks pass.
9. Workstation and Adelie NixOS closures build from committed source.
10. The disposable self-hosted Pi journey renders and validates the generated Ansible configuration without touching the live Pi.
