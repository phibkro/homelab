# Outcome monitoring activation - September 21, 2026

This report records the deployment of outcome monitoring and recovery-evidence freshness monitoring. Times use UTC.

## Scope

The deployment used these commits:

- `50dee37 feat(observability): monitor service outcomes`
- `51ba227 fix(observability): probe LAN edge through split DNS`
- `efcf947 fix(backups): grant freshness checker read access`

The operator authorized activation on Pi, Adelie, and workstation.

## Pi

The Pi deployment completed without a failed Ansible task. The deployment added the outcome probes, notification rules, and two freshness timers.

At `2026-09-21T21:54:31Z`, these timers were active:

- `pi-restic-freshness.timer`
- `pi-restic-evidence-freshness.timer`

The first deployed edge probes failed because Gatus resolved public routes to the public Caddy address. The Pi uses split DNS for these routes.

Commit `51ba227` changed the probes to use the Pi LAN address with the public host name. After deployment, the four edge probes passed:

- `edge-audio`: HTTP 200
- `edge-auth-challenge`: HTTP 401
- `edge-media`: HTTP 200
- `edge-requests`: HTTP 200

The Gatus result endpoint exposed 39 healthy probes after one full 60-second interval.

## Adelie

The Adelie activation installed the fleet freshness timer. The active system was:

`/nix/store/f8wrpgfv9xsf4g9f78153irx4h41asll-nixos-system-adelie-26.11.20260910.8ce4ef6`

The host state was `running`. The timer was active, and its first service run returned `Result=success` and `ExecMainStatus=0`.

## Workstation

The first workstation freshness run failed. Restic repositories on OneTouch use dynamic-user ownership and mode `0700`.

The checker ran as root with an empty capability set. Therefore, it could not read those repository directories.

Commit `efcf947` gives the checker `CAP_DAC_READ_SEARCH` only on hosts with local freshness mounts. The read-only Restic queries still use `--no-lock`.

The corrected workstation system was:

`/nix/store/pi0s0dggvjxwn152p20dj1s5r09q7mz8-nixos-system-workstation-26.11.20260910.8ce4ef6`

The host state was `running`. A direct run of `restic-snapshot-freshness.service` returned `Result=success` and `ExecMainStatus=0`.

## End-to-end result

`just test-observability` passed after the three activations:

- All 7 VictoriaMetrics scrape targets were healthy.
- Workstation exposed 276 process series.
- The Pi heartbeat age was 58 seconds.
- All 39 Gatus probes were healthy.
- The workstation snapshot-freshness timer was active.
- Both Pi freshness timers were active.

## Production notification acceptance - September 22, 2026

The operator approved one controlled Gatus failure and recovery journey.

An ephemeral `synthetic-alert-acceptance` probe targeted closed port 18080 on
the Pi. The probe used a five-second interval and a failure threshold of one.

At `2026-09-22T02:15:14Z`, the ntfy feed returned the Gatus failure alert. Its
message reported one failed probe and status code 0.

A temporary loopback HTTP server then made the same probe pass. At
`2026-09-22T02:21:49Z`, the ntfy feed returned the resolved notification after
two successful probes.

The temporary server and probe were removed. The restored monitoring topology
then passed `just test-observability`:

- All 7 VictoriaMetrics scrape targets were healthy.
- Workstation exposed 281 process series.
- The Pi heartbeat age was 0 seconds.
- All 37 permanent Gatus probes were healthy.
- The workstation snapshot-freshness timer was active.
- Both Pi freshness timers were active.

## Boundaries

This report proves the deployed state at each observation time. It does not
prove reboot persistence or notification delivery to a specific mobile device.
