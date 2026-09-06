---
name: add-service
description: Add or relocate a homelab service, including inventory placement, runtime configuration, routes and backup intent.
---

Read `docs/reference/module-authoring.md`, `inventory/workloads.nix` and one
existing service with similar storage/authentication needs before writing.

For workstation, keep pure metadata in `services/<service>/manifest.nix`
and NixOS implementation in its `nixos.nix`. Reuse an existing coupled cluster
when the new workload shares its lifecycle. For Pi, implement it under the
service's `ansible/` directory and select it in `infra/pi/playbooks/pi.yml`.

Inventory owns placement and shared endpoint facts. Derive Pi routes through
the existing generator. Declare service data, backup intent, filesystem access
and authentication using the established contracts. Consult the reference for
the current option shapes instead of copying historical examples.

Run relevant Nix and Ansible checks, regenerate catalogs, and exercise the real
service journey after approved deployment. A Nix adapter test does not establish
that an Ansible-managed production service works.
