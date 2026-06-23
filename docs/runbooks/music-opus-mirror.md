# Music: phone ⇄ FLAC library ⇄ Opus mirror

The operator's music workflow. Mixes **declarative** (the `music-ingest` +
`music-mirror` systemd units) and **runtime** (Syncthing folders, WebUI/API-managed,
`overrideFolders = false`) state, so this runbook is the single place the runtime
half is written down. Last reworked 2026-06-23 when the ingest half went live.

## Goal

Download lossless FLAC on the phone, have it land in the workstation library, and
listen in compressed Opus on the phone (~9× smaller). Acquisition is
**SpotiFLAC-Mobile on the phone** (no Qobuz/Spotify in-app auth).

```
  IN  ─ phone /Music/flac ──Syncthing(sendreceive)──▶ ws STAGING /mnt/media/staging/music-flac
        music-ingest.timer (15m): MOVE stable flac+art ──▶ /mnt/media/library/music (MASTER)
        the MOVE deletes from staging ──Syncthing──▶ phone frees its FLAC
  OUT ─ music-mirror.timer (15m): master ──opusenc 128k──▶ /mnt/media/library/music-opus
        Syncthing "Music-Opus" (sendonly) ──▶ phone /Music/opus  (Opus + embedded covers)
```

Net: the phone stores only Opus; new downloads round-trip in, become Opus, come back.

## The load-bearing invariant: the phone never touches the master

The master (`/mnt/media/library/music`, tier **irreplaceable**) is shared in Syncthing
with **ws + aurora only** — the phone was structurally **severed** from it (device
removed, not just paused). The phone only ever touches **staging**, which is transient,
outside the master, and the only place the ingest deletes from. So a phone glitch
(reporting "empty", a contamination loop) can damage at most staging — never the master.
This replaces the old "keep the Music folder paused" stopgap; pausing was a flippable
toggle, the sever is structural.

## What's LIVE (2026-06-23)

| Unit | Module | Does |
|---|---|---|
| `nori.musicIngest` | `modules/services/music-ingest.nix` (+ `.sh`) | 15m timer: MOVE complete, stable FLAC **and art** staging→master. Stable-file guard (no Syncthing `.tmp` sibling AND mtime > window), blake3 dedupe, conflict→`.conflicts/`, crash-safe cp→fsync→rename→unlink, umask-honoring chmod so the media group can read. |
| `nori.musicMirror` | `modules/services/music-mirror.nix` | 15m timer: `tonic-mirror` (`inputs.tonic`) opusenc master→music-opus. Idempotent (mtime + SOURCE_BLAKE3 stamp), `--serial`-pinned (byte-deterministic), embedded FLAC cover art carries through. |

Syncthing folders (runtime, per device):

```
  master "Music"        /mnt/media/library/music        receiveonly  ws + aurora   (phone SEVERED)
  staging "Music-Staging" /mnt/media/staging/music-flac sendreceive  ws + pixel8a
  "Music-Opus"          /mnt/media/library/music-opus   sendonly     ws → pixel8a
```

Verified end-to-end: the phone's entire SpotiFLAC backlog (282 FLAC) ingested into the
master; phone freed ~12 GB; covers show via embedded art. After de-duplicating the old
`flac (tonic push)/` copy (see below) the library is **286 FLAC / 11 GB → 285 Opus / 1.2 GB**.

**3 source FLAC are corrupt** (`NOT_A_FLAC`, fail opusenc) — re-download on the phone:
`The Art of Peer Pressure – Kendrick`, `ict – Oklou`, `Ophelia – PinkPantheress`.

## Gotchas (each one cost a live debugging cycle — all load-bearing)

1. **`.stfolder` marker** — Syncthing refuses to sync a folder whose `.stfolder` marker
   is missing ("folder path missing", state=error). A pre-created dir needs the marker
   (or Syncthing creates it if it can write). Toggle pause to restart the folder runner
   after fixing.
2. **Syncthing sandbox bind** — `nori.harden.syncthing` binds only `library` + `downloads`;
   any NEW path (the staging dir) is invisible inside the service namespace until added to
   `nori.harden.syncthing.binds`. Symptom mimics #1 ("folder path missing") even though the
   dir exists on the host. A host-level write-test is misleading — it doesn't go through the
   sandbox.
3. **Syncthing UMask** — default `0022` makes received dirs `drwxr-sr-x` (no group write), so
   another media-group user can't delete from them. Set `systemd.services.syncthing.serviceConfig.UMask = "0002"`.
4. **Ingest 0600** — `mktemp` makes the crash-safe temp `0600` and rename preserves it, so
   moved files are owner-only → `music-mirror`/Navidrome (media group) get PermissionError.
   The ingest now chmods the temp to the umask-derived mode before rename. (If you ever see
   `Permission denied` reading a master FLAC: `find … ! -perm -g+r -exec chmod 0664`.)
5. **GrapheneOS storage scope** — Syncthing-Fork defaults to limited storage on GrapheneOS;
   grant **All files access** so it can receive Opus AND delete (free) FLAC. Embedded-art
   covers need nothing extra — opusenc carries the FLAC PICTURE block into the Opus.
6. **opusenc non-determinism** — without `--serial`, opusenc randomizes the Ogg stream serial
   per encode → same FLAC, different bytes. Harmless for the mirror (it skips via the stamp),
   but a forced re-encode would re-ship every Opus. `library_mirror` now pins `--serial`.

## Resolved incidents (kept for context)

- **Contamination loop:** the phone's Opus folder was once *nested inside* the FLAC folder,
  so Opus swept into `library/music`. Resolved structurally: staging is **outside** the
  master, ingest moves only flac+art (never opus), and the phone's opus path is a sibling
  of its flac path. Stray opus that lands in the phone's `/Music/flac` is contained in
  staging and cleanable (`find staging -iname '*.opus' -delete`).
- **Near-deletion:** a send-only phone reporting an empty `/Music/flac` could once have
  deleted the receive-only master. Resolved by the sever — the phone is no longer a device
  on the master folder at all.

## Dedup note (one-time, 2026-06-23)

The phone's library was a re-acquisition of an older `music/flac (tonic push)/` subtree.
Compared via **PCM-decode hash** (FLAC STREAMINFO MD5 was disabled → all-zero → useless;
opusenc isn't a valid comparator either, non-deterministic): 279 bit-identical + 3
corrupt-in-both ⇒ fully redundant. Deleted (recoverable from restic/snapshots).

## Levers

```
  systemctl start music-ingest.service    # force an ingest sweep now
  systemctl start music-mirror.service    # force a mirror sweep now
  journalctl -u music-ingest.service      # last ingest (logs ingested/deduped/conflicted/unstable)
  journalctl -u music-mirror.service      # last mirror (done/skip/fail per file)
  tonic-mirror --dry-run                  # what would transcode (hand-run)
  Syncthing API (ws): http://127.0.0.1:8384/rest  (apikey in ~/.config/syncthing/config.xml)
    GET /rest/config/folders · GET /rest/db/status?folder=music-staging  — folders are runtime, not nix
```
