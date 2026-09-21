# User-data recovery drill — September 21, 2026

This drill proved bounded recovery from every declared user-data root. It used
source revision `92c4cfa5129e` before the restore-drill correction described
below. Times are UTC unless specified otherwise.

## Scope

The `user-data` repository protects three roots:

- `/home`;
- `/srv/nori`;
- `/srv/share`.

The drill created a fresh snapshot and restored one stable regular file from
each root. It compared bytes and filesystem metadata without reading file
contents into the report or agent context.

## Fresh snapshot

The normal `restic-backups-user-data-onetouch.service` unit completed
successfully at 01:18:12. Restic created snapshot `07167648` at 01:08:28.
The snapshot covered all three declared roots on the workstation.

A restore-size scan measured the latest user-data snapshot before the fresh
backup:

| Measure | Value |
|---|---:|
| Files | 9,998,531 |
| Logical restore size | 751.885 GiB |
| Free workstation root space | 169 GiB |

The deployed quarterly drill still expected approximately 99 GiB and attempted
a complete restore under `/var/restore-test`. The current snapshot cannot fit
there. Running that unit would fail or fill the root filesystem.

## Bounded restore

The recovery selected these declared samples:

| Root | Sample | Size | Mode |
|---|---|---:|---:|
| `/home` | `/home/nori/.ssh/config` | 198 bytes | `0600` |
| `/srv/nori` | `/srv/nori/Documents/abstract_algebra.pdf` | 210,081 bytes | `0644` |
| `/srv/share` | `/srv/share/projects/homelab/flake.lock` | 25,719 bytes | `0644` |

Restic restored three files and their parent directories from snapshot
`07167648`. The restored data totalled 230.467 KiB.

All three restored files matched their live sources byte-for-byte. File size,
mode, numeric owner, numeric group, and modification time also matched for each
file. The restored SHA-256 digests were:

- `080c79d7858eb931504754d5df737d52a20f6cd084dd9f9b0e3816ce8cf18482`;
- `34896e35b82f5ad7ce6c0055b84fa604650ebf2b004d787b38cf7d4ed7c6d9ab`;
- `2edf35ae72ec7429e97fd0615d3634f90e1e63c81c81cf6e063182ee9043595d`.

## Restore-drill correction

The source configuration now declares `restoreSamples` beside the `user-data`
backup intent. The backup schema rejects a sample outside that job's include
roots.

The quarterly `restore-drill-user-data` unit now restores only the declared
samples into a root-only directory. It requires every sample to exist and be
readable, computes each SHA-256 digest, and reports the restored file count and
size.

The generated source script was evaluated and executed directly against the
fresh snapshot. It reported:

```text
PASS — files=3 bytes=235998 samples=3
```

The source change also removes user-data and media repositories from the
root-filesystem `restore-drill-all` unit. A complete large-repository restore
must use an explicit destination with enough capacity. The corrected units
require the next workstation activation before their timers use this behavior.

## Cleanup

Both disposable restore directories were removed after verification. The
root-owned drill log remains at
`/var/log/restore-drill/20260921-032044.txt` under the existing 180-day log
retention policy.

## Evidence boundary

This drill establishes:

```text
all declared user-data roots → fresh OneTouch snapshot
                             → bounded selective restore
                             → byte and metadata comparison
```

It does not establish:

- restoration of all 751.885 GiB or all 9,998,531 files;
- an atomic snapshot across the three live roots;
- application-level validity for databases stored under those roots;
- recovery of excluded caches;
- recovery after loss of both the workstation and OneTouch disk;
- complete workstation reconstruction;
- full Restic pack integrity, which belongs to `restic check` and read-data
  sampling.

The next recovery stage should cover media metadata or complete host
reconstruction. A full user-data restore requires a disposable destination
larger than the measured logical snapshot size.
