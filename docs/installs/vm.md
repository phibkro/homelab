---
summary: Current disposable VM checks for NixOS modules and the Ansible-managed Pi.
---

# Disposable VM verification

The repository no longer exposes a `nixosConfigurations.vm-test` installation
target. Do not use the former manual UTM procedure as workstation-install
evidence.

Use the repository's metadata-selected checks instead. They build disposable
machines and do not activate a production host.

## NixOS checks

Run one exact VM check while developing:

```bash
just check-vm e2e-restic-backup
```

Run every registered NixOS VM check only when the broader evidence is needed:

```bash
just check-vm
```

`just check-all` includes these VM checks and every fast check. These commands
can consume substantial memory and build time. Run only one heavy job for this
project at a time.

The current VM check registry lives in `lib/flake-parts/checks/e2e.nix`.
`just check-vm <name>` rejects names outside that registry.

## Pi checks

Pi is a Debian appliance managed by Ansible. It has no production NixOS
configuration. Use the separate disposable ARM journey:

```bash
just pi::test
```

This journey verifies fresh convergence, repeated convergence, recovery, and
reboot behavior in a disposable guest. It does not prove production
credentials, physical Pi hardware, attached storage, or live network paths.

## Evidence limits

A disposable VM proves only the boundary exercised by that check. It does not
prove that the workstation can be installed, that a production activation ran,
or that off-LAN access works.

For a real workstation install, use
[`baremetal.md`](baremetal.md). For production activation, use the
[deployment reference](../reference/deployment.md). Record the exact check name,
source revision, dirty state, result, and any untested boundary.
