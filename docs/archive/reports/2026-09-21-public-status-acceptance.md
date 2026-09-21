# Public status production acceptance — September 21, 2026

All times are UTC.

## Scope

This acceptance covered the Cloudflare Worker, D1 migration, scheduled probes,
and authenticated maintenance and incident history. It did not change the home
router. The ADR-0006 router cutover remains operator-gated.

## Deployment

The reviewed plan proposed two updates:

- update the existing D1 database with additive migration `0002_status_events.sql`;
- update the Worker and create its `MUTATION_TOKEN` secret binding.

The production deployment completed successfully. A later Worker update added
Cloudflare's `global_fetch_strictly_public` compatibility flag. This flag makes
same-zone probes use the public Internet path.

The final production API uses schema version 2. The public response contains the
three published components and no internal topology fields.

## Observations

| Time | Observation |
| --- | --- |
| 13:24 | The version 2 API returned the three published components. Initial component states were `unknown`. |
| 13:24 | Maintenance `668e018d-ac3e-4d90-b36a-2097abe09f16` opened for `audio`. The public state changed to `maintenance`. |
| 13:28 | The scheduled trigger persisted the first probe results. Every component gained a non-null `checkedAt` value. |
| 13:25–13:29 | Navidrome stopped and restarted on the workstation. The direct endpoint changed from HTTP 502 to HTTP 302. |
| 13:50 | The maintenance event completed with a second immutable update. |
| 13:50 | Incident `373b97ad-fed7-4d9a-8b33-1769b8d093f4` opened for `audio`. The public state changed to `degraded`. |
| 13:50 | The incident resolved with a second immutable update. The terminal history remained public. |
| 13:50 | Scheduled probes reported all three components as `outage` with fresh timestamps. |

## Result

The following gates passed:

- the two-minute Cloudflare trigger executes and persists probe rows;
- `unknown` states are replaced by real scheduled results;
- the authenticated maintenance journey creates and completes public history;
- the authenticated incident journey creates and resolves public history;
- maintenance and incident state overrides probe state while active;
- terminal event updates remain visible after completion;
- Navidrome was restored and `navidrome.service` returned to `active`.

The external recovery transition remains unproven. The Worker correctly reports
`outage` because WAN TCP 443 is not yet forwarded to `192.168.1.225:443`.
Internal workstation requests use local routing, so their HTTP 302 responses do
not prove off-LAN reachability.

After the ADR-0006 router cutover, wait for an `operational` scheduled result.
Then stop and restart Navidrome once more. Record the full
`operational → outage → operational` transition before closing external
acceptance.
