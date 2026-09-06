# Direct music-ingest acceptance

Date: 2026-09-06

The direct structure candidate passed the bounded acceptance gates from a
clean, locally committed snapshot. The tested snapshot is:

- path: `/tmp/homelab-direct-music-20260906-191200`
- commit: `3f4f98cbae8ce4f790ac9d36929bb60e68d8f368`
- tree: `bfb4a5bddf6866aa789a79cc8f3bde020580abc9`
- files captured: 689
- snapshot status: clean

## Gates

| Gate | Canonical command | Result | Evidence |
| --- | --- | --- | --- |
| Fast Nix checks | `devenv shell -- just check` | PASS; 34 checks, including the registered runtime check's `90 passed, 0 failed` | session `26759`; `/tmp/homelab-direct-music-fast.log` |
| Migration coherence | `devenv shell -- just check-migration` | PASS; `all path references resolve` | session `68677`; `/tmp/homelab-direct-music-migration.log` |
| Runtime recipe | `devenv shell -- just test-music-ingest` | PASS; exit 0 | session `41888`; `/tmp/homelab-direct-music-runtime.log` |
| Runtime detail | `devenv shell -- music-ingest-runtime` | PASS; `90 passed, 0 failed` | session `77940`; `/tmp/homelab-direct-music-runtime-detail.log` |
| Disposable VM | `devenv shell -- just check-vm e2e-music-ingest` | PASS; NixOS test finished in 19.46s and cleaned up QEMU | session `97180`; `/tmp/homelab-direct-music-vm.log` |
| Workstation closure | `devenv shell -- just build` | PASS; `nh os build . -H workstation`, no activation | session `36341`; output `/nix/store/k05lb7cmzpg6ss7jplssaxwm1xx5dhcj-nixos-system-workstation-26.11.20260904.801bef6`; `/tmp/homelab-direct-music-build.log` |

The VM exercised the real `music-ingest.service` and timer. Its fixture mounts
staging and inflight on one disposable filesystem and master on another. The
test asserts the scheduled timer, service user/group and supplementary groups,
UMask, bind paths, mount dependencies, and filesystem hardening. It publishes
fixture bytes and asserts the resulting mode and `root:media` ownership,
recovers a pre-existing inflight claim, and verifies duplicate idempotence.

The conflict case starts the real service, observes exit status 3 and systemd
`Result=exit-code`, verifies that master bytes remain intact, checks the
quarantine path, and waits for the fixture-local `notify@` OnFailure observer to
write its activation marker. The permission case produces an actual `find:
Permission denied` traversal failure and asserts the service failed with
`Result=exit-code`. No production `/mnt/media` path or external ntfy endpoint
is used.

## Acceptance fixes exercised

The final candidate includes the pure evaluation fixture's explicit
`nixpkgs`, `pkgs`, `lib`, and `system` inputs, so the check does not reopen the
`/nix/store` source with `getFlake`. The registered runtime check packages the
whole `services/music-ingest` directory so its test can resolve the adapter
sibling. The subprocess synchronization shims use `/bin/sh`, and the direct
fixtures are statix-clean. These fixes were included before the tested commit.

Selected tested-content SHA-256 values are:

```text
services/music-ingest/nixos.nix        f50a980d2fc6ef789a5e862a655d40b640400dae7a4c357200f2aa1d0680a4d8
services/music-ingest/ingest.sh        1681726a1ca862e6b308c4f08b90fc57353264cd4eadb5edd15584f4b30b4a4b
services/music-ingest/tests/eval.nix  127b68969b02d6d72d6b40b325d77d4d742080bc2daec4b39471ed337e8e8365
services/music-ingest/tests/nixos.nix 5308a6458cc715e0e5d769f64c32c9bca24fae3e2226a5b219d709106e071d0b
services/music-ingest/tests/runtime.sh f091a659d3759e6161ed44613a28df96c748c7773bb6c5b778f877a8b91d0957
infra/workstation/music-ingest.nix  555fdf253de140b591b07b1a7c99ae00f4b9920c25a885cb531d82edf37c8395
infra/workstation/media-storage.nix   0626bd8c1cd5983d81cc397582b3314a6e38f59988471e5a581c0f3ad840491d
```

## Provenance and preservation

The source worktree index SHA-256 was
`2abefd0fb40a53170729e51d8f2be71c18196af1cd0b0670328a0b721badcefc` before
and after snapshot capture. Its index tree was
`c7edf8248cfde917f4117d37cfda951ee639560e` at both measurements. Every file
listed by the snapshot's normal Git index compared byte-for-byte with the
source candidate; the result was PASS. No source staging or source commit was
performed for this report.

The exact candidate is retained in a local Git bundle:

`/srv/share/projects/homelab/.worktrees/two-host-migration-evidence/direct-music-ingest/direct-music-ingest-acceptance.bundle`

Bundle SHA-256:
`7dc985d8a844ee250d1c6ed94ca0bf0ee517b45e9f4582628b32c3b4e59d2a9e`

`git bundle verify` reported a complete history containing the acceptance
commit. Final logs, provenance, hashes, and the bundle verification are in:

`/srv/share/projects/homelab/.worktrees/two-host-migration-evidence/direct-music-ingest/`

## Scope limit

These gates establish behavior in the disposable fixture, Nix evaluation,
runtime filesystem fixture, VM systemd environment, and workstation closure
build. They do not establish production deployment, activation, real Syncthing
behavior, live `/mnt/media` behavior, external ntfy delivery, or provider
network availability.
