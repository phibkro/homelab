# Legacy implementation-plan index

The `/improve` skill generated these advisor handoffs on 2026-07-14 against
commit `0cef85b`. They are historical evidence. They do not define current
work, requirements, or execution order.

Use [the roadmap](../../roadmap.md) for current work. These files are separate
from the product and migration plans in [the plan archive](../plans/). Do not
execute a plan from this index without current operator direction.

## Planning baseline

At planning time, the audit recorded this result:

```text
nix flake check --print-build-logs → exit 0
```

The audit also recorded these read-only evaluation results:

```text
aurora nori.replicas:       5 entries
workstation nori.replicas:  0 entries
workstation verifier units: 0

btrbk-family-replica: actual sender, no nori.harden TemporaryFileSystem
btrbk-replication:    phantom profile, no ExecStart
```

These results describe the audit basis on 2026-07-14. They do not describe the
current system.

## Archived plan links

| Plan | Title | Archive note |
|---:|---|---|
| [001](001-isolate-pavilion-sops.md) | Isolate pavilion from privileged SOPS secrets | Archived advisor plan |
| [002](002-rotate-console-credentials.md) | Replace committed placeholder console credentials | Archived advisor plan |
| [003](003-enforce-real-unit-hardening.md) | Bind `nori.harden` profiles to real systemd units | Archived advisor plan |
| [004](004-authenticate-suwayomi-api.md) | Require Suwayomi authentication on exempt API requests | Archived advisor plan |
| [005](005-place-replica-intent-on-target.md) | Make replica intent identical on source and target hosts | Archived advisor plan |
| [006](006-fail-closed-backup-runtime-tests.md) | Make backup runtime checks fail closed | Archived advisor plan |
| [007](007-resolve-manual-backup-units.md) | Resolve manual backups to generated job-target units | Archived advisor plan |
| [008](008-run-replica-verifiers-now.md) | Run current replica verification instead of trusting stored success | Archived advisor plan |
| [009](009-claim-music-before-ingest.md) | Claim music files atomically before publish and deletion | Archived advisor plan |
| [010](010-fail-closed-observability.md) | Fail closed on unreadable heartbeat and undelivered disk alerts | Archived advisor plan |
| [011](011-gate-third-party-agent-skills.md) | Gate third-party agent skills behind reviewable hashes | Rejected on 2026-08-11 after the third-party skill inputs were removed |
| [012](012-verify-authelia-client-registry.md) | Compare live Authelia clients with declared OIDC routes | Archived advisor plan |
| [013](013-repair-active-documentation.md) | Repair active documentation and enforce routing paths | Archived advisor plan |
| [014](014-single-runtime-test-environment.md) | Run runtime tests in one pinned tool environment | Archived advisor plan |

## Audit findings preserved

| Finding recorded by the audit | Plan |
|---|---|
| Pavilion received every shared SOPS secret | [001](001-isolate-pavilion-sops.md) |
| A temporary shared console credential granted a path to passwordless root | [002](002-rotate-console-credentials.md) |
| Hardening profiles targeted phantom units, while the btrbk sender lacked hardening | [003](003-enforce-real-unit-hardening.md) |
| Suwayomi `/api/*` bypassed Authelia while application authentication was disabled | [004](004-authenticate-suwayomi-api.md) |
| Replica declarations existed only in Aurora evaluation | [005](005-place-replica-intent-on-target.md) |
| Backup tests passed with no snapshots and lexical sibling prefixes | [006](006-fail-closed-backup-runtime-tests.md) |
| `just backup` targeted a unit shape that did not exist | [007](007-resolve-manual-backup-units.md) |
| Replica tests trusted indefinitely old stored success results | [008](008-run-replica-verifiers-now.md) |
| Music ingest could publish one source version and delete another | [009](009-claim-music-before-ingest.md) |
| Heartbeat unreadability and ntfy delivery failure passed green | [010](010-fail-closed-observability.md) |
| External instruction content entered auto-discovery without a review artifact | [011](011-gate-third-party-agent-skills.md) |
| The Authelia test promised client comparison but checked only secret files | [012](012-verify-authelia-client-registry.md) |
| Active documentation pointed to old files, paths, roles, and domain names | [013](013-repair-active-documentation.md) |
| Runtime loops started ad-hoc Nix shells repeatedly | [014](014-single-runtime-test-environment.md) |

## Archive boundaries

The individual plans preserve their original dependencies, scope, stopping
conditions, rejected findings, and audit coverage limits. These records explain
why the audit made each recommendation. They do not establish present system
state or future work.
