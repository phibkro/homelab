# Ansible Pi Plan B

## Goal

Provision a replaceable ARM64 Debian/Raspberry Pi OS appliance from this
repository without building a Raspberry Pi kernel. The first tracer bullet
boots a disposable ARM64 guest, converges the real playbook twice, and serves
DNS through a rootful, systemd-restored Podman Pi-hole container.

## Constraints

- `inventory/` remains the authority for homelab identity and DNS records.
- Production secrets never enter Git; emulation uses explicit test values.
- SecretSpec declares and resolves production secrets through keyring-first,
  environment-fallback providers; Ansible receives them only in child process
  environment.
- The playbook does not mutate the physical Pi unless the operator selects the
  production inventory explicitly.
- Network exposure remains default-deny. Pi-hole exposes DNS and its LAN admin
  port only; DHCP remains on the Genexis router.
- Flash writes stay bounded: no disk swap and volatile journald.
- The existing NixOS Pi build and deployment path remain intact during the
  experiment.

## First milestone

1. `nix develop` provides Ansible, linting, QEMU and cloud-image tools.
2. `just pi check` passes syntax, Ansible lint, YAML lint and ShellCheck.
3. `just pi test` boots an ARM64 Debian guest under QEMU.
4. The production playbook converges twice against that guest.
5. The second convergence reports zero changes.
6. A DNS query against the guest's forwarded port returns a Pi-hole response.
7. The host firewall defaults to deny and production container ports bind only
   to the inventory-declared LAN address.
8. Production host identity and DNS records are generated from
   `lib.noriInventory`; generated topology is never committed.
9. A guest reboot restores the Podman container and DNS without another
   Ansible convergence.
10. Production plan/deploy commands require a pinned SSH host key; deploy also
    requires an exact `pi@<inventory-address>` confirmation.

## Second milestone

- Install Tailscale from its checksum-pinned official Debian repository.
- Enable forwarding and declare subnet/exit-node preferences.
- Keep enrollment disabled unless an external auth key and explicit inventory
  choice request it; tailnet route approval remains an operator action.

## Current verified state (2026-08-29)

- The live appliance is the Debian/Ansible/Podman Plan B host at
  `192.168.1.225`. Pi-hole DNS is available on port 53 and its temporary
  direct administration fallback is `http://192.168.1.225:8081/admin/`.
- The disposable ARM64 QEMU guest has passed two convergences, including the
  Caddy/Pi-hole HTTPS canary (HTTP 308 redirect, Pi-hole login redirect, and
  unknown-host rejection), and passed the same contract after a guest reboot.
  The same Caddy configuration is deployed on the physical Pi: its trusted
  certificate, HTTP 308 redirect, Pi-hole login redirect, unknown-host 404,
  and zero-change second convergence were verified from the workstation.
- Router DHCP DNS cutover, physical reboot/power-cycle, and tailnet-client DNS
  checks remain pending. The Pi is not currently enrolled in Tailscale, so
  off-LAN DNS has not been accepted.
- The Genexis router continues to provide DHCP. Its DNS setting has not been
  changed as part of this canary.

## Rollback artifact and safety boundary

The previously built NixOS image was copied as a rollback artifact and its
compressed bytes were verified before this migration continued:

```text
Source: /tmp/pi-nixos-sd-image/sd-image/nixos-image-sd-card-26.11.20260822.2c423e0-aarch64-linux.img.zst
Backup: /home/nori/Downloads/nixos-pi-backup-2026-08-29.img.zst
SHA-256 (source and backup): fb8728306032039eb982f151046357be454627c54177e7a0fe443fed1b695d0b
```

The backup is not flashed or activated. The live appliance remains the
Debian Plan B system. Until physical reboot acceptance passes, retain the
direct Pi-hole administration fallback on port 8081. A failed Caddy
cutover must leave DNS on port 53 and this fallback available; do not change
router or tailnet DNS until the acceptance gates below pass.

## Migration backlog after the tracer bullet

The Pi-hole DNS service is live, but its administration UI is temporarily
LAN-only HTTP on port 8081. The migration is complete only after the following
work is deployed and verified in order.

### Network cutover

- [ ] Enroll the appliance in Tailscale using SecretSpec-provided credentials.
- [ ] Approve its `192.168.1.0/24` subnet route and exit-node capability in the
  Tailscale admin console.
- [ ] Point Genexis DHCP DNS at `192.168.1.225`, renew representative wired and
  Wi-Fi client leases, and verify local and public resolution.
- [ ] Point tailnet DNS at the appliance and verify resolution from an off-LAN
  tailnet client.

### HTTPS entry and identity plane

Completed Caddy canary work:

- [x] Exercise the Caddy/Pi-hole HTTPS contract in the disposable ARM64 VM,
  including idempotent convergence and recovery after a guest reboot.
- [x] Deploy Caddy with inventory-derived routes and persistent certificate
  storage on the physical appliance.
- [x] Serve the Pi-hole administration UI through Caddy over trusted HTTPS on
  its inventory-declared hostname while retaining application authentication.
- [ ] Verify the accepted HTTPS and DNS contract from a tailnet client and
  exercise certificate renewal before restricting direct port 8081 access.
- [ ] Deploy Authelia and restore the inventory-declared OIDC clients and
  access policies.
- [ ] Deploy Cloudflare DDNS for routes explicitly marked internet-reachable.

### Monitoring and alerting plane

- [ ] Deploy Gatus and restore DNS, HTTP and service health checks.
- [ ] Deploy ntfy and verify a real alert from a failed test unit reaches an
  off-appliance client.
- [ ] Deploy the Beszel hub and reconnect the existing agents.
- [ ] Deploy VictoriaMetrics and VictoriaLogs, reconnect their producers, and
  verify fresh metrics and logs arrive after an appliance restart.

### Recovery and final retirement

- [ ] Deploy restic-to-Aurora for every stateful appliance path and complete a
  restore drill from the resulting repository.
- [ ] Reboot the physical appliance and verify Pi-hole DNS, HTTPS entry,
  identity, monitoring, alerting and backup timers recover without Ansible.
- [ ] Update the Pi failure runbook and architecture documentation from the old
  NixOS/Blocky service layout to the Debian/Ansible/Podman layout.
- [ ] Retire the old NixOS Pi deployment path only after the new appliance has
  passed the reboot and restore checks.

## Acceptance matrix

Run these checks in order. “Pending” means the check has not been accepted;
passing the QEMU canary does not satisfy a physical or off-LAN row.

| Plane | Client or condition | Check and expected result | Status |
| --- | --- | --- | --- |
| DNS | Appliance/LAN baseline | Query `@192.168.1.225` for an internal record and a public name; Pi-hole answers and public resolution succeeds. | Verify again after cutover |
| DNS | Wired LAN client | Renew its DHCP lease, confirm the intended router/Pi-hole resolver, and resolve both an internal record and a public name. | Pending router DHCP DNS cutover |
| DNS | Wi-Fi LAN client | Repeat the wired-client checks over Wi-Fi, including lease renewal and both internal/public names. | Pending router DHCP DNS cutover |
| DNS | Off-LAN tailnet client | Enroll the Pi, approve the route as applicable, point tailnet DNS at it, and resolve both names from a client not on the LAN. | Pending; Pi is not enrolled |
| HTTPS | Disposable ARM64 QEMU guest | `just pi test` verifies HTTP 308, Pi-hole HTTPS login redirect, unknown-host 404, idempotence, and recovery after guest reboot. | Complete (canary only) |
| HTTPS | Physical LAN client | Verify the inventory hostname, trusted certificate, redirect/login contract, unknown-host rejection, and idempotent deployment. | Complete from workstation |
| HTTPS | Physical tailnet client and renewal | Repeat the HTTPS contract off-LAN and exercise the renewal path before removing normal access to port 8081. | Pending Tailscale enrollment |
| Recovery | Physical reboot/power-cycle | Reboot the Pi and confirm DNS, Caddy HTTPS, and all accepted services recover without another Ansible run. | Pending |
| Rollback | Caddy or DNS cutover failure | Keep Pi-hole DNS on port 53 and restore the direct admin fallback at `http://192.168.1.225:8081/admin/`; defer router/tailnet DNS changes and revert only the failed service. | Fallback documented; exercise pending |
| Rollback | NixOS image recovery | Preserve `/home/nori/Downloads/nixos-pi-backup-2026-08-29.img.zst`; verify SHA-256 against `fb8728306032039eb982f151046357be454627c54177e7a0fe443fed1b695d0b` before any restore or flash. | Artifact verified; not activated |

The physical reboot, restore drill, and off-LAN checks are cutover gates. Do
not mark the migration complete or retire the Nix path until all three, plus
the service and monitoring checks, are accepted.
