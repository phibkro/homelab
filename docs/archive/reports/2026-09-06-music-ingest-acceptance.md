# Music-ingest acceptance report

Date: 2026-09-06

## Verdict

The independently generated music-ingest module passes the bounded compiler,
runtime, and disposable NixOS VM acceptance journey at the clean candidate
snapshot below. This accepts the generated module for the slice. It does not
authorize workstation cutover or deployment.

## Exact candidate

The run used this disposable committed snapshot, whose source tree was copied
from the migration worktree after the compiler freeze:

```text
path:   /tmp/homelab-music-slice-20260906-NEj2jG
commit: bcc850e56633a82b3c3deb7fb22c20f5b24e18da
tree:   010a9ad4bff6215a870dd5b7d237ac3186bdf3b8
status: clean (0 bytes from git status --porcelain=v1)
```

The final candidate content hashes are:

| File | SHA-256 |
| --- | --- |
| `model/music-ingest.json` | `e1edab59ec58e122bbd19532dbd2de1b32253b23458ba84fb57b094ccb169c10` |
| `compiler/src/HomelabCompiler.jl` | `ea9aac2fec59437719dcf1e827cfa9efc695960b8260a6b5d3b4cb5465ea7cb9` |
| `realizations/music-ingest.nix` | `7dbca0586a0f9939942ab747f7b298680ef0d754046c224cc6adf43b5459ceaa` |
| `generated/music-ingest.nix` | `dd685440fadc480ad933b91a8483c696defdce898876885375c205ed7b75285d` |
| `generated/music-ingest.svg` | `26d95ef0b633856835b591b1ffd6e368ccb26df82219622543f93baa9d91c3e1` |
| `generated/music-ingest.evidence.json` | `164fa2c72c08b0c633ad6ccb3d1e6a6a8c91411677b11c841cbdc92b4a2b5f76` |
| `implementations/music-ingest/music-ingest.sh` | `e01f087fad46d89954dfab1230f491f3de644a229f8c665348a730929d171f8d` |
| `tests/runtime/music-ingest/music-ingest.test.sh` | `60da51073ada1c705fa43c21d58eaa9241ade67920ea1f2ff71e8af90edd3973` |
| `tests/vm/music-ingest/e2e.nix` | `684dab2cfc0456a5d4a8adca73adcb7c3a0cf43a0651599c61580060ab05f0e5` |

## Gates and commands

The compiler checks ran from the snapshot's `compiler/` directory with its
locked `devenv` environment and root flake nixpkgs pin.

Gate A, model validation, passed all 48 checks: canonical typed model 10/10,
required rejections 30/30, deterministic artifact derivation 6/6, and escaped
Nix interpolation 2/2.

```console
devenv shell -- test
# canonical typed model 10/10
# required rejections 30/30
# deterministic artifact derivation 6/6
# Nix string interpolation is escaped 2/2
```

Gate B, deterministic generation and Nix evaluation, passed freshness,
artifact provenance, all seven negative path/filesystem cases, and the
positive generated unit/timer evaluation. The evaluated `BindPaths` includes
staging/.conflicts and tmpfiles includes its matching rule.

```console
devenv shell -- check-generated
# generated artifacts are current
# behavior: 1 process, 7 typed flows
# realization: 10 requirements, 10 grants, 4 resource bindings, 1 hosting relation
# runtime obligations: 5

devenv shell -- check-nix
# all seven negative path/filesystem cases passed
# positive generated unit/timer evaluation passed
# BindPaths includes staging/.conflicts and tmpfiles includes its matching d rule
```

Gate C, the disposable filesystem journey, passed the packaged runtime suite:

```console
devenv shell -- check-runtime
# === RESULT: 83 passed, 0 failed ===
```

Gate D, the disposable systemd journey, passed. The disposable VM was invoked
through the same compiler `devenv` shell. There
was no committed VM script in the compiler devenv, so the bounded `runNixOSTest`
expression was passed directly to `nix build`:

```console
devenv shell -- nix build --no-link --print-build-logs --max-jobs 1 \
  --impure --expr 'let root = builtins.getFlake "/tmp/homelab-music-slice-20260906-NEj2jG";
    system = builtins.currentSystem;
    pkgs = import root.inputs.nixpkgs { inherit system; };
    in import "/tmp/homelab-music-slice-20260906-NEj2jG/tests/vm/music-ingest/e2e.nix"
      { inherit pkgs; lib = pkgs.lib; }'
# exit 0; test script finished in 19.08s
```

The VM used two disposable tmpfs mounts. Staging and inflight shared one
device; master used another. The real generated unit ran as
`music-ingest:music-ingest` with supplementary `media`, `UMask=0002`, the
packaged `/nix/store` adapter, the generated bind paths, mount dependencies,
and the generated hardening settings.

The guest observations were:

- the timer was enabled, active, and scheduled through its monotonic
  `OnBootSec` deadline without waiting an hour;
- a stable nested FLAC was published with exact fixture bytes and
  `music-ingest:media:664` ownership/mode, while staging and inflight were
  empty afterward and systemd reported success/status 0;
- an identical second publication preserved the master digest, removed only
  its owned source, and reported success/status 0;
- a differing master preserved the master bytes, moved the claim to
  `.conflicts`, returned status 3 with `Result=exit-code`, and activated the
  fixture-local `notify@music-ingest.service`, which wrote the observed
  `activated` marker;
- a root-only traversal boundary produced a real `find` permission error,
  left the fixture file in place, and left the systemd unit failed with a
  nonzero status; and
- the initial namespace setup failure caught a missing generated quarantine
  directory. The compiler correction added the role-derived tmpfiles rule
  `d <staging>/.conflicts 02770 music-ingest media - -`, after which the same
  real unit passed.

## Fixture corrections during acceptance

The VM fixture remained the only VM-owned source. Its corrections were:

- use `nodes.music`, the NixOS test driver's declared node binding;
- remove a readonly `nixpkgs.config` override when the pinned package set is
  supplied by the expression;
- observe monotonic timer scheduling because the generated timer uses
  `OnBootSec`/`OnUnitActiveSec`;
- request every systemd property that the hardening assertions inspect; and
- make the local observer write a constant activation marker, so the test
  observes execution of the generated `OnFailure` target rather than relying
  on template-instance argument formatting.

The compiler-owned correction creates the quarantine path before the generated
service's `BindPaths` namespace is established. The generated Nix artifact and
SVG bytes did not change; the realization and evidence were refreshed.

## Preservation evidence

The source migration worktree was never committed, reset, or used as the VM
working tree. Its index tree remained `c7edf8248cfde917f4117d37cfda951ee639560e`
and its `.git/index` SHA-256 remained
`2abefd0fb40a53170729e51d8f2be71c18196af1cd0b0670328a0b721badcefc`.

The preservation audit found no environment contamination in the original
checkout. Its HEAD remains `b3a85506c650f5c66060acd1ab6434e06684569f`, all 59
current changes are staged, and its index was rewritten at 15:39 after the
01:23 snapshot. The current HEAD diff retains 57 baseline paths, adds
`modules/home/omp/config.yml` and `modules/home/saturation-alert.nix`, and
contains a changed `flake.lock` blob. Git does not identify the actor for
those changes.

The 18 accepted candidate files under `compiler/` (excluding `.devenv`),
`model/`, `realizations/`, `generated/`, `implementations/`,
`tests/runtime/music-ingest/`, and `tests/vm/music-ingest/` compare
byte-for-byte between the clean snapshot and source clone: 18 matched, 0
mismatched.

The complete preservation streams captured during the audit and their
manifest are outside the source clone at:

`/srv/share/projects/homelab/.worktrees/two-host-migration-evidence/music-ingest/`

That directory also contains the final Gate A/B/Nix/runtime logs and the final
VM log. It contains the verified complete Git bundle
`music-ingest-acceptance.bundle` for the exact snapshot as well. The report
itself is intentionally uncommitted in the source clone.

## Limits

This is disposable tmpfs and NixOS test-driver evidence. It does not prove
power-loss durability on production Btrfs or hardware, a live Syncthing or
Lidarr journey, external ntfy delivery, workstation activation, deployment,
rollback, or restoration of real `/mnt/media`. The VM was directly invoked
through the compiler devenv because the current flake e2e check set does not
yet register `music-ingest-generated-vm`; that registration remains a separate
integration task.
