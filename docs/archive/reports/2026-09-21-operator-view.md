# Operator view acceptance - September 21, 2026

All times in this report are UTC.

## Scope

This acceptance covers the read-only operator view in
`docs/specs/2026-09-21-operator-view-design.md`.

The command joins three fact classes:

- `declared` contains the current inventory configuration.
- `observed` contains timestamped health and backup results.
- `proven` contains accepted recovery reports and their gates.

The implementation does not add a service registry, database, browser service,
or mutation API.

## Source relationships

The inventory supplies service identity, placement, routes, authentication,
probe names, and deployment ownership. Evaluated backup jobs supply the NixOS
backup intent. `inventory/backup.nix` supplies the Pi backup intent and its
workload relationship.

VictoriaMetrics supplies the current Gatus result series. The CLI keeps each
sample timestamp. NixOS backup results come from the matching systemd units.
The Pi result comes from `pi-restic-freshness.service`, which inspects all eight
remote repositories.

The recovery registry supplies historical report references. These references
do not imply current health or backup freshness.

## Live acceptance

At `2026-09-21T17:52:15+00:00`, this command completed successfully:

```bash
just overview --json
```

The snapshot contained 47 active service workloads.

| Observation | Count |
|---|---:|
| Monitored and healthy | 32 |
| Unmonitored | 15 |
| Pi backup was fresh at the last repository check | 7 |
| NixOS backup unit had a successful last run | 19 |
| Backup was not applicable | 17 |
| No correlated backup job was declared | 4 |

The health source and backup observation source both reported `ok`. No monitored
service reported a failing or unknown state.

Pi-hole reported `healthy` from its HTTP and DNS probes. Its repository check
reported `fresh-at-last-check` from 13 seconds earlier. The view linked the
`pihole-service` recovery report.

Jellyfin reported `healthy`. Its backup unit reported `last-run-success` from
39,846 seconds earlier. The view linked the `jellyfin-metadata` recovery report.

The terminal table also completed through this command:

```bash
just overview
```

## Static checks

These checks completed successfully:

```bash
nix build .#operator-view --no-link
nix build .#checks.x86_64-linux.operator-view --no-link
just overview --help
```

The generated declaration contained every active service workload exactly once.
The package check also covers these joins:

- Jellyfin to its native-auth route, Gatus probe, and backup job.
- Pi-hole to both Gatus probes, the Ansible owner, repository check, and
  recovery report.
- Caddy to its host probe and Pi backup without a fabricated route.

The runtime fixtures reject stale or future health samples. They also reject
future backup timestamps and preserve missing health sources as `unknown`.

## Evidence limits

`last-run-success` is systemd unit evidence. It is not direct Restic snapshot
inspection. `fresh-at-last-check` describes the last Pi repository check. Its
age remains visible in the JSON and terminal output.

`not-declared` means that the view found no backup job for that workload. A
shared data job can still protect related data. `unmonitored` means that the
inventory declares no Gatus probe for that workload.

Gatus stores short response history in memory. A Pi or container restart removes
that history. VictoriaMetrics preserves the current result samples used by this
acceptance.
