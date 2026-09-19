# Adelie source admission evidence — September 19, 2026

This report records source checks only. It does not authorize or prove an
installation, activation, disk operation, network enrollment, reboot, or
connection to Adelie.

## Source under test

- Commit: `4775e05` (`feat(adelie): enforce source-only admission`)
- Host target: `nixosConfigurations.adelie.config.system.build.toplevel`
- Contract: `docs/specs/2026-09-19-adelie-admission.md`

## Observed evidence

| Boundary | Command or inspection | Result |
|---|---|---|
| Full fast checks | `devenv shell -- just check` | All 40 fast checks passed after the generated topology was refreshed. |
| Adelie closure | `nix build .#nixosConfigurations.adelie.config.system.build.toplevel --no-link` | Passed from clean committed source. Output: `/nix/store/4gcv9nyj7zgsk9ivw6dlrxgf0b4fqgdz-nixos-system-adelie-26.11.20260910.8ce4ef6`. |
| Deployment boundary | `nix run .#deployment-plan -- --host adelie` | One Adelie build target; empty `plans`, `applies`, and `verifies`. |
| Runtime selection | `eval-adelie-admission` | Beszel agent, node exporter, and Vector exist. Attic publication and backup-target services do not exist. |
| Disk boundary | `eval-adelie-admission` | One disk: the exact Samsung 990 Pro by-id path. Evaluated filesystems contain no `/mnt/media` or `/mnt/backup`. |
| Secret boundary | Nix evaluation, SOPS decryption, and recipient search | Adelie has no evaluated SOPS secrets. Both encrypted corpora decrypt for an authorized editor. Adelie's former age recipient is absent from policy and current ciphertext metadata. |

## Source changes

- Attic cache publication moved from the common base to the workstation-only
  Attic workload.
- The Beszel hub public key became a non-secret declarative trust value.
- OIDC raw client secrets and templates now exist only on each backend host.
  Authelia retains the hashes that it needs on its own host.
- Adelie uses wired DHCP for the later bootstrap. Wi-Fi secret enrollment is
  outside this milestone.
- Adelie's broad SOPS recipient was removed from current policy and ciphertext.
  Historical ciphertext can still contain material encrypted to that key.

## Unproven and unauthorized

No command contacted Adelie. No disk was partitioned. No installer, system
switch, Tailscale enrollment, SSH trust bootstrap, secret enrollment, reboot,
or service relocation occurred.

A later physical milestone must verify the Samsung device, UEFI mode, host-key
provenance, narrow secrets, network identity, first boot, rollback, expected
services, and absent portable disks before activation is accepted.
