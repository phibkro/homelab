# Music: phone → FLAC staging → master library

The lossless-music acquisition path. Declarative bindings live in
`nori.services.music-ingest`; Syncthing folder membership remains
runtime-managed and must be observed separately.

## Flow

```text
phone /Music/flac
  └─ Syncthing (send/receive)
       └─ workstation /mnt/media/staging/music-flac
            └─ music-ingest.timer
                 └─ claim stable FLAC + cover art atomically
                      └─ /mnt/media/staging/.music-ingest-inflight
                           └─ verified publish
                                └─ /mnt/media/library/music (irreplaceable master)
```

The ingest removes only the claim it owns after durable publication. Syncthing
can observe the removed staging entry; actual propagation to the phone depends
on runtime folder membership and connectivity. Listening is served from the
master by Navidrome; there is no local Opus mirror or Tonic dependency.

## Load-bearing invariant

**The phone never participates in the master Syncthing folder.** It can write
only to transient staging outside `/mnt/media/library`. A phone or Syncthing
error can therefore damage staging, never the irreplaceable master.

The module asserts that staging, inflight, and master are pairwise disjoint in
both ancestor directions. Staging and inflight must share a filesystem so the
claim rename is atomic. Keep the phone structurally absent from the master
folder rather than relying on a pause toggle.

## Live units and paths

| Item | Value |
|---|---|
| Option | `nori.services.music-ingest` |
| Manifest | `services/music-ingest/manifest.nix` |
| Runtime | `services/music-ingest/nixos.nix` |
| Workstation binding | `infra/workstation/music-ingest.nix` |
| Timer | `music-ingest.timer` |
| Staging | `/mnt/media/staging/music-flac` |
| Inflight claims | `/mnt/media/staging/.music-ingest-inflight` |
| Master | `/mnt/media/library/music` |
| Conflict quarantine | `<staging>/.conflicts/` |

A file is claimed only after its mtime exceeds the stability window and no
Syncthing temporary sibling exists. Existing identical files are deduplicated;
different content at the same relative path is quarantined while the master is
left untouched. The crash-safe path is staging → atomic inflight claim →
master-local copy → fsync → rename → remove owned claim. Interrupted claims are
processed before new staging files on the next sweep.

## Runtime Syncthing shape

```text
master  "Music"          workstation; phone absent (check runtime membership)
staging "Music-Staging"  workstation + phone; send/receive
```

`overrideFolders = false`, so verify this membership in Syncthing’s runtime UI
when onboarding or replacing a device.

## Gotchas

1. Syncthing requires its `.stfolder` marker and write access to staging.
2. `nori.harden.syncthing.binds` must include staging or the path is invisible
   inside Syncthing’s mount namespace.
3. Syncthing and ingest use `UMask=0002`; otherwise media-group readers such as
   Navidrome cannot read received files.
4. `mktemp` starts at mode `0600`; the ingest script applies the umask-derived
   final mode before rename.
5. GrapheneOS Syncthing needs **All files access** to receive and delete staged
   FLACs.

## Operate and verify

```bash
sudo systemctl start music-ingest.service
journalctl -u music-ingest.service
devenv test
```

The test covers stability guards, durable claim recovery, replacement and
destination races, deduplication, conflict quarantine, permissions, path
escapes, nested paths, cover art, serialization, and rerun idempotence.
