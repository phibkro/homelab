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

- [ ] Deploy Caddy with inventory-derived routes and certificate storage.
- [ ] Serve the Pi-hole administration UI through Caddy over HTTPS on its
  inventory-declared hostname; retain its application authentication and stop
  advertising port 8081 as the normal operator entry point.
- [ ] Verify certificate issuance/renewal, HTTP-to-HTTPS redirect, DNS and web
  access from LAN and tailnet clients before restricting direct port 8081
  access further.
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
