---
summary: Admit Adelie as a buildable minimal NixOS host without installation, activation, service migration, or disk movement.
date: 2026-09-19
status: frozen; source implementation and removal of Adelie's broad SOPS access authorized; no installation or activation authorized
owner: operator
---

# Adelie source admission

## Goal

Adelie has a reviewed, buildable NixOS closure for its Samsung system disk and fleet agents. This milestone stops before physical installation or activation.

The closure must make unrelated authority unavailable. It must not inherit application credentials, cache-publisher credentials, stateful services, portable disks, or backup ownership through a shared profile.

## User journey

1. Inspect Adelie's host declaration and exact Samsung disk identity.
2. Evaluate the derived workload realizations.
3. Confirm that only `beszel-agent` and `node-exporter` realize on Adelie.
4. Build `nixosConfigurations.adelie.config.system.build.toplevel` from committed source.
5. Ask the deployment planner for Adelie and receive one build target with no apply command.
6. Inspect the build and acceptance record without contacting, installing, booting, or activating Adelie.

## Source authority

- `inventory/hosts.nix` owns Adelie's identity, tags, capabilities, profiles, and NixOS backend.
- Service manifests own workload placement.
- `infra/adelie/` owns hardware and the Samsung system-disk layout.
- `users/nori/adelie.nix` owns the minimal operator home.
- Portable disk identity and attachment remain in `inventory/disks.nix`.

Profiles must not add undeclared workload authority. A read-only binary-cache client is baseline infrastructure. Cache publication is workload authority and belongs only to the selected Attic realization.

## Runtime allow-list

The phase-one Adelie closure can provide:

- the common NixOS and operator baseline;
- OpenSSH with existing operator public keys;
- Tailscale software, without enrollment in this milestone;
- Vector log forwarding;
- `beszel-agent`;
- the `node-exporter` workload, including its node and process exporters.

It must not provide:

- Attic publication or its push token;
- an Attic server;
- application, media, acquisition, database, backup-source, or backup-target services;
- workstation desktop modules;
- Pi appliance services.

## Secret boundary

Adelie must not be a recipient for the privileged fleet or application secret corpora.

Before a later activation, each required Adelie input must be either:

- a non-secret source value, such as a public trust key; or
- an Adelie-specific encrypted value with an explicit, narrow recipient set.

A network scan is not identity proof. A later encrypted host input requires an Ed25519 host key observed at Adelie's physical console and an independently compared age recipient. Rekeying current files does not revoke access to historical ciphertext.

## Storage boundary

The only disk this host declaration can partition is:

```text
/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_1TB_S7HDNU0L409926V
```

The declaration can create a GPT, EFI system partition, and Btrfs root on that disk. Applying it is destructive and is not authorized by this milestone.

IronWolf Pro and OneTouch remain attached to workstation. Adelie's evaluated disk and filesystem plan must contain neither disk, `/mnt/media`, nor `/mnt/backup`.

Before a later install, a physical-console procedure must:

1. disconnect IronWolf and OneTouch;
2. match Samsung model, serial, capacity, transport, and resolved by-id path;
3. confirm UEFI boot mode;
4. record the data-preservation decision;
5. obtain fresh authority immediately before partitioning.

## Identity boundary

The inventory value `100.107.90.3` is intent, not runtime proof. A later Tailscale enrollment must verify the new node ID, DNS name, and addresses through an authenticated control-plane view. It must reject stale or duplicate Adelie nodes and must not restore another host's Tailscale state.

The first SSH connection must use a host key independently observed at the physical console. `ssh-keyscan` can collect a candidate but cannot establish trust.

## Installation and activation boundary

This milestone must not run:

- Disko against a live disk;
- `nixos-install` or `nixos-anywhere`;
- `nixos-rebuild switch`, `nh os switch`, or `activate-test`;
- `just push adelie` or any remote rebuild command;
- Tailscale enrollment;
- a reboot or physical host contact.

The generic remote commands remain capable of bypassing the deployment planner. Their existence is not activation authority.

## Later physical acceptance

A separate operator-authorized milestone must prove:

1. the exact Samsung disk identity and UEFI environment;
2. unique SSH and SOPS identity provenance;
3. installation and first boot;
4. expected Tailscale node identity;
5. reboot persistence and previous-generation rollback;
6. Pi reachability from Vector and both metrics agents;
7. absence of every undeclared service and portable disk;
8. temperatures, networking, and GPU discovery without granting a GPU workload.

## Acceptance

Source admission is complete when:

1. Adelie evaluates with exactly `beszel-agent` and `node-exporter` realizations.
2. The closure has no Attic push secret, seed service, or watch service.
3. The Attic realization on workstation still owns cache publication.
4. Adelie cannot decrypt privileged fleet or application secret files.
5. The evaluated disk plan names only the exact Samsung by-id path.
6. IronWolf, OneTouch, `/mnt/media`, and `/mnt/backup` are absent from Adelie's disk and filesystem plan.
7. The deployment planner emits one Adelie build and no plan, apply, or verify command.
8. The committed Adelie toplevel builds successfully.
9. Fast evaluation checks pass.
10. Evidence states that no install, activation, enrollment, reboot, disk operation, or Adelie contact occurred.

## Rejected alternatives

### Broad SOPS recipient access

Rejected because minimal host admission does not justify access to backup, identity-provider, Cloudflare, Attic administration, or application credentials.

### Cache publication in the base profile

Rejected because it hides a credentialed network writer outside workload placement. Read-only substitution can remain common; publication follows the Attic workload.

### Network-scanned trust bootstrap

Rejected because reachability and a presented key do not establish machine identity.

### Combined host and storage migration

Rejected because a boot failure must not also move primary media and backup failure domains.

## Change control

This contract is frozen for source admission. Removing Adelie from broad existing SOPS files is part of this admission. Future recipient enrollment, physical installation, activation, service relocation, and disk movement require explicit authority and separate acceptance evidence.
