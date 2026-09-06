---
name: add-host
description: Add a physical or virtual homelab host with an explicit NixOS or Ansible deployment owner.
---

Read `docs/reference/module-authoring.md` and `inventory/hosts.nix` before editing.
Host enumeration comes exclusively from inventory keys; directories do not activate hosts.

Declare exactly one backend. NixOS hosts provide system/home module paths and
hardware configuration under `infra/<host>/`; Ansible hosts provide a management
root and explicit plan/apply/check commands. The existing Pi remains Ansible-owned.
Select workloads explicitly through inventory profiles and host additions.

Update shared topology facts in inventory, then regenerate documentation and
check the deployment projection. Run backend-appropriate evaluation/build or
Ansible checks, and verify the actual installation journey before claiming an
operational host. Disk formatting, secret-recipient changes and activation
require the applicable operator authority; a host declaration grants none of them.
