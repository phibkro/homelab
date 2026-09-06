# Complete repository reorganization acceptance

This report records the final disposable acceptance of the complete repository
reorganization. The runtime-tested candidate is commit
`35343845706a9af194716e82a48929ba4e8512aa` in
`/srv/share/projects/homelab/.worktrees/complete-migration`. Its tree is
`4276881d0f8e003d735dd5f93656c6ecc0abb054`, and the worktree was clean before
and after acceptance.

## Gates

| Gate | Command and result | Evidence |
| --- | --- | --- |
| Fast checks | `devenv shell -- just check`; 33 checks; exit 0 | `complete-migration-fast-3534384.txt`, `complete-migration-fast-3534384.log` |
| Migration path checks | `devenv shell -- just check-migration`; exit 0 | `complete-migration-paths-3534384.txt`, `complete-migration-paths-3534384.log` |
| Workstation closure | `devenv shell -- just build`; final retry exit 0 | `complete-migration-build-3534384.log` |
| NixOS VM checks | All seven VM derivations were run on `d4558ea1b1a43c31bffa38cedea60080ce1eec18` and passed. The final candidate's seven VM derivation paths compare byte-for-byte equal to that run, so no unchanged VM journey was repeated. | `complete-migration-nix-vm-d4558ea.log`, `complete-migration-nix-vm-equivalence-3534384.log`, `complete-migration-nix-vm-equivalence-3534384.diff` |
| Pi disposable acceptance | `PI_VM_REUSE=true PI_VM_STATE_DIR=/srv/share/projects/homelab/.worktrees/complete-migration/.artifacts/pi-vm/run.ROhdmdZL just pi::test`; exit 0 | `complete-migration-pi-vm-3534384-retry.log`, retained `result.json` |

The first Pi attempt on `d4558ea` exposed the old `backup` role alias in the
disabled-backup fixture. The checked-in fixture and VM runner were repaired in
`abc6dd9` and `78b3b07`, then the combined candidate was tested. The final Pi
run completed enabled-first and enabled-second convergence with
`ok=164 changed=0 unreachable=0 failed=0`, restored the disposable backup and
rejected the SFTP traversal, completed disabled-first convergence with the
expected unit removal changes, completed disabled-second convergence with
`ok=2 changed=0 unreachable=0 failed=0`, rebooted, and reached `complete`.
The retained result records `outcome=passed`, `exitCode=0`, and an unchanged
repository working-state hash. No QEMU, Ansible, or runner process remained after
the run.

The first build and derivation probes also contain sandbox-only failures before
the same canonical commands were retried with local Nix daemon access. The
final build and comparison receipts are exit 0; the original boundary errors
are retained in their logs.

After the report-only cleanup, `devenv shell -- just check-migration` was run
again and exited 0; its receipt is
`complete-migration-paths-66e8-cleanup.log`.

## Projection checks

The final Pi generator was run from the candidate with
`devenv shell -- bash infra/pi/scripts/generate-inventory.sh`. Its normalized
output has SHA-256
`991e4cb6fb42765a2cca5f770b7741ef84d35316065f446d92d0795b7341d4db`, exactly
matching the v2 baseline (`cmp` exit 0). The public inventory was evaluated
from `.#lib.noriInventory` and the explicit generator-derived projection audit
passed: 34 routes, 4 OIDC clients, 35 Gatus endpoints, 5 scrape jobs, 36
Pi-hole DNS records, and the active `music-ingest` workload on `workstation`.
Evidence is in `pi-generated-inventory-final-3534384*`,
`pi-generated-inventory-v2*`, `inventory-final-3534384*`, and
`pi-public-projection-audit-3534384.txt`.

The preserved `pi-public-projection-audit-3534384-initial-fail.txt` records an
ordering-only comparator failure. The helper initially treated uniqueness as
order-preserving; the generator uses jq `unique_by`, which sorts its result.
The helper was corrected to model that explicit transformation and reran with
`result=PASS`. No candidate source file changed for this correction.

The direct music-ingest runtime fixture also records `90 passed, 0 failed` in
`/srv/share/projects/homelab/.worktrees/two-host-migration-evidence/direct-music-ingest/runtime-detail.log`;
the final fast gate included the packaged `music-ingest-runtime` derivation.

The strict workstation v2 projection was evaluated on the final candidate with
exit 0. Compared with the accepted `d4558ea` projection it has no differences
apart from the source revision field. Compared with the earlier `4f4dcab` v2
baseline, the sole retained difference is the source path in a non-executed
systemd notify-helper comment. The command, normalized projections, and empty
diff are recorded in `workstation-semantic-after-3534384-v2-command.txt`,
`workstation-semantic-after-3534384-v2-normalized.json`, and
`workstation-semantic-d4558ea-to-3534384-v2.diff`.

## Preservation and custody

The original worktree remained at HEAD
`b3a85506c650f5c66060acd1ab6434e06684569f`; its captured baseline file-hash
check exited 0. Its current staged state is recorded in
`preservation-audit-final-3534384.txt`; the worktree diff is empty and the
captured staged diff remains present. Direct `git diff HEAD --binary` hashes
match the captured before state: `58e38b633ae4e7cd2fd4c256eab0dcf240c20c19a3e34cdf05c8a2a6cde527ba`
for the original and `a9c1be30ef19703e7c57350d6814060c9692fe10054b84542c71880978c3d969`
for two-host. The two-host source worktree remained at HEAD
`06de3381bbe307c08a7ee8524f652a314965cb41`; its captured baseline file-hash
check also exited 0. These checks cover the captured files and make no claim
about later additions or about which operator made any surrounding dirty-tree
changes.

The tested candidate was clean at both runtime and report capture. The empty
`modules/.gitkeep` directory marker is removed by the report-only cleanup
commit because it has no runtime module content. The original and prior
two-host source checkouts were not staged or committed by this acceptance lane;
the independent candidate clone necessarily contains the tested candidate and
report commits. Neither source checkout was activated, deployed, or pushed.

The exact tested candidate is preserved as
`/srv/share/projects/homelab/.worktrees/two-host-migration-evidence/full-migration/complete-migration-3534384.bundle`.
`git bundle verify` passed; bundle SHA-256 is
`f98ba1bb380a569a9d533f7cd3ce32b40fd5b172745578aa062828375670edbd`.

## Scope limits

Pi acceptance used the disposable emulated ARM guest, local backup fixture,
and local test inventory. It did not use production credentials, a physical Pi,
the production plan/deploy/enroll recipes, or a provider. The workstation
closure was built without activation. The final seven Nix VM derivations were
identity-compared with the actual seven-run `d4558ea` result rather than
re-executed after changes limited to the Pi harness, migration guards/docs,
tests, and a Grafana comment.
