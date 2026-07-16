# Music: phone → FLAC staging → master library

The live acquisition path for lossless music. Declarative behavior lives in
`nori.musicIngest`; Syncthing folder membership remains runtime-managed.

## Flow

```text
phone /Music/flac
  └─ Syncthing (send/receive)
       └─ workstation /mnt/media/staging/music-flac
            └─ music-ingest.timer
                 └─ MOVE stable FLAC + cover art
                      └─ /mnt/media/library/music (irreplaceable master)
```

The move removes the staging copy, so Syncthing propagates the deletion back to
the phone. Listening is served from the master by Navidrome; there is no local
Opus mirror or Tonic dependency.

## Load-bearing invariant

**The phone never participates in the master Syncthing folder.** It can write
only to transient staging outside `/mnt/media/library`. A phone or Syncthing
error can therefore damage staging, never the irreplaceable master.

The module asserts that staging is not nested under the master path. Keep the
phone structurally absent from the master folder rather than relying on a
pause toggle.

## Live units and paths

| Item | Value |
|---|---|
| Option | `nori.musicIngest` |
| Module | `modules/services/music-ingest.nix` |
| Timer | `music-ingest.timer` |
| Staging | `/mnt/media/staging/music-flac` |
| Master | `/mnt/media/library/music` |
| Conflict quarantine | `<staging>/.conflicts/` |

A file moves only after its mtime exceeds the stability window and no
Syncthing temporary sibling exists. Existing identical files are deduplicated;
different content at the same relative path is quarantined while the master is
left untouched. The crash-safe path is copy → fsync → rename → unlink.

## Runtime Syncthing shape

```text
master  "Music"          workstation + aurora only; phone absent
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
nix shell nixpkgs#b3sum --command bash modules/services/music-ingest.test.sh
```

The test covers stability guards, deduplication, conflict quarantine,
permissions, nested paths, cover art, and rerun idempotence.
