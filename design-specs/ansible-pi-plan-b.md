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

## Deferred after the tracer bullet

Live Tailscale enrollment/route approval, Caddy, Authelia, Cloudflare DDNS,
Gatus, ntfy, Beszel, VictoriaMetrics/Logs, and restic-to-Aurora.
