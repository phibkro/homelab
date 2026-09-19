# Pi failure

Recovery target: under two hours when required state is available; no current
backup coverage or production recovery time has been established.
Pi is a Debian appliance managed by Ansible under `infra/pi/`. NixOS rollback,
impermanence, and `nixos-anywhere` instructions do not apply to this target.

## Triage

Check Pi reachability from a trusted LAN or tailnet device. Use the production
SSH user, address, and port declared by the production inventory generator;
do not assume the workstation SSH settings apply. Inspect failed systemd units,
container state, logs, disk usage, and network connectivity through that session.
The September 6 observation found a host-key mismatch against existing trust;
no remote Pi session was established. Verify the key through an independently
trusted console before updating the pin. Do not bypass host-key checking.

Workstation backends may remain available through explicitly exposed routes.
Pi-hosted DNS, authentication, ingress, monitoring, and routing may be down even
when a backend process is healthy. Check each dependency before declaring an
application recovered.

## Configuration failure

1. Identify the last working committed Pi configuration and the failed change.
2. Prepare its reviewed correction or revert in the repository.
3. Run `just pi::check`, the disposable convergence test `just pi::test`, and
   `just pi::plan`. Check production target identity and the proposed changes.
4. After operator approval, run `just pi::deploy` and inspect live services and
   routes. Ansible convergence is not an atomic NixOS generation rollback.

## Hardware or root filesystem failure

1. Preserve the failed medium where recovery may still be possible. Provision
   the supported Debian image on a verified replacement medium through a
   separately reviewed installation procedure.
2. Establish the expected management connection and public host identity.
   Restore production SecretSpec inputs through their protected provider; the
   repository contains configuration, not the secret values.
3. Review and converge `infra/pi/` through its production plan/deploy commands.
4. Re-enroll Tailscale through `just pi::enroll` if needed, with operator
   approval. Do not run two nodes concurrently with a copied node identity.
5. Inspect any surviving historical archives and their protected recovery
   credentials. Do not assume Pi snapshots exist on
   MP510 or OneTouch, or that a disposable restore helper remains installed.
   If a usable snapshot exists, restore to scratch, inspect its contents, and
   copy selected data into stopped services. Validate databases separately.
   If no usable copy exists, document the lost state and reconfigure the
   affected service rather than claiming it was restored.

The [OneTouch cutover runbook](onetouch-backup-cutover.md) describes backup transport
identity, repository isolation, and restore checks. Destination policy lives in
`inventory/backup.nix`; workstation restore evidence does not establish Pi coverage.

## Temporary failover

Changing DNS alone does not relocate Caddy or authentication. Promoting
workstation to the entry plane requires a separately reviewed placement,
addressing, secrets, and application-state migration. Tested Nix entry-plane
adapters are not a completed Ansible-to-Nix production recovery procedure.
Any DNS/provider change requires explicit operator approval.

## Verify recovery

- Verify DNS from LAN and tailnet clients, HTTPS certificate validation,
  authentication, and representative backend routes without bypassing TLS.
- Verify subnet/exit routing for clients that use Pi and check monitoring and
  off-host heartbeat delivery.
- Confirm deployed backup policy matches the reviewed inventory. Preserve
  historical recovery credentials and archives. Use the OneTouch runbook to
  establish fresh Pi backup and restore evidence after recovery.
- Record the revision, restored snapshot IDs, remaining failures, and elapsed
  recovery time. Keep historical archives intact.
