# Music-ingest first-slice independent review

Date: 2026-09-06

## Verdict

The standalone runtime component is accepted and ready to freeze at the
reviewed content hashes below. Its real-filesystem fixture exercises the
bounded shell-level behavior without touching `/mnt/media` or a live service.

Gate C remains incomplete as a whole: this shell fixture places staging,
inflight and master under one `/tmp` filesystem. It observes rejection when
staging and inflight use different devices, but does not observe successful
publication to a different master filesystem. The disposable NixOS VM is the
planned evidence for that production-shaped boundary. Gate D and workstation
cutover are outside this result.

## Reviewed snapshot

| File | SHA-256 |
| --- | --- |
| `implementations/music-ingest/music-ingest.sh` | `e01f087fad46d89954dfab1230f491f3de644a229f8c665348a730929d171f8d` |
| `tests/runtime/music-ingest/music-ingest.test.sh` | `60da51073ada1c705fa43c21d58eaa9241ade67920ea1f2ff71e8af90edd3973` |

The hashes were identical before and after the independent run.

## Evidence observed

The following commands were run from the isolated migration worktree:

```console
PATH=/nix/store/n0kjqa4jilnpp6h04lqlwa9zch8x808a-b3sum-1.8.5/bin:$PATH \
  timeout 60s bash tests/runtime/music-ingest/music-ingest.test.sh
# RESULT: 83 passed, 0 failed

bash -n implementations/music-ingest/music-ingest.sh \
  tests/runtime/music-ingest/music-ingest.test.sh
# exit 0

/nix/store/ixvpvkr2s92pbi6si1ki8yk3fs1gvlf2-shellcheck-0.11.0-bin/bin/shellcheck \
  implementations/music-ingest/music-ingest.sh \
  tests/runtime/music-ingest/music-ingest.test.sh
# exit 0
```

The fixture directly observed stable ingestion, freshness and Syncthing-temp
guards, dedupe, conflict quarantine without clobber, recovery of retained
claims, replacement of the staging path after claim, and serialized adapter
invocations. It also exercised these earlier counterexamples:

- an atomic fresh-inode swap between the age check and claim is retained until
  that inode reaches its own stability window;
- a real `SIGKILL` after the copy temp exists leaves an owned claim and temp,
  and the next sweep removes the stale temp, publishes the pre-kill bytes, and
  leaves a new staging replacement untouched;
- a destination directory created before publication is not treated as the
  final file or used as a move target; the claim is quarantined;
- an unreadable staging subtree makes the whole scan fail before an eligible
  peer is processed;
- lexical and symlink root aliases are rejected after normalization; and
- existing destination-parent, destination-file, and claim-path symlinks fail
  closed in the tested arrangements and recover after the symlink is removed.

This establishes behavior at those exact subprocess and filesystem
interleavings. It does not establish safety against hostile same-user mutation
at every path-operation boundary; the implementation explicitly assumes
cooperating writers replace files atomically.

## Evidence not established here

- successful cross-filesystem staging-to-master publication;
- systemd unit, timer, principal, mount dependency, exit classification, or
  `OnFailure` behavior;
- power-loss, kernel, Btrfs, or drive-cache durability;
- a live Syncthing, Lidarr, notification, or workstation journey; or
- deployment, rollback, or restoration of real media.

Those claims require the disposable VM and, later, an explicitly authorized
workstation cutover. No runtime or test source was changed during this review.

## Compiler review status

The compiler/model review is pending its writer's final handoff. During the
moving revision review, authority matching had already been strengthened to
include the hosted principal, process, resource and operation, and capability
bindings were checked against the hosted handler and machine. Two remaining
relations were reported to that writer for correction: resource-binding
machines must agree with capability/hosting placement, and a handler's declared
protocol capabilities must either constrain its bindings or be removed from
the canonical model. No compiler gate is claimed by this report.
