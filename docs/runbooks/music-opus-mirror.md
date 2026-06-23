# Music: FLAC library → Opus mirror → phone

The operator's music workflow, captured 2026-06-23. Mixes **declarative** (the
`music-mirror` systemd unit) and **runtime** (Syncthing folders, which are
WebUI/API-managed — `overrideFolders = false`) state, so this runbook is the
single place the runtime half is written down.

## Goal

Download lossless FLAC, listen in compressed Opus on the phone to fit ~9× more.
No Qobuz/Spotify in-app auth — acquisition is **SpotiFLAC-Mobile on the phone**.

```
  phone: SpotiFLAC ⬇ FLAC ──Syncthing──▶ workstation /mnt/media/library/music
                                          (lossless master · Navidrome serves it)
  music-mirror.timer (15 min): library/music ──opusenc 128k──▶ library/music-opus
  Syncthing "Music-Opus" (sendonly) ──▶ phone  (Opus · ~9× smaller)
```

## What's LIVE and working (2026-06-23)

- **`music-mirror`** systemd unit (declarative, `modules/services/music-mirror.nix`,
  enabled on workstation): timer every 15 min runs `tonic-mirror`
  (`inputs.tonic` backend) → keeps `library/music-opus` current. Idempotent
  (mtime fast-path + SOURCE_BLAKE3), idle-priority, group-writable output.
  Verified: 282 FLAC → 281 Opus, 11 GB → 1.2 GB (9.2×). 1 source FLAC corrupt
  ("The Art of Peer Pressure" — re-download).
- **Opus on phone: 100%** — Syncthing "Music-Opus" folder (sendonly →
  pixel8a only) delivered all 281 tracks. Point the phone's player at it.
- **GrapheneOS gotcha (load-bearing):** Syncthing-Fork defaults to *read-only*
  storage on GrapheneOS → "folder marker missing" + no Opus received. Fix:
  grant Syncthing **All files access** (Settings → Apps → Syncthing →
  Permissions). Write access is required to *receive* Opus AND for any future
  auto-delete of the phone's FLAC.

## What's PAUSED and why (do not blindly resume)

- **Syncthing "Music" (FLAC) folder is PAUSED** on workstation. It protects the
  282-FLAC master. It was the site of two incidents:
  1. **Loop / contamination:** the phone's Music-Opus folder was placed *inside*
     the Music folder (`/Music/opus` under `/Music`), so Opus swept back into
     `library/music` (344 leaked .opus, 34 GB `.stversions` hoard). Cleaned:
     master is now 282 FLAC / 0 opus / 11 GB; `.stversions` purged.
     **Invariant: the phone's Music-Opus path must be OUTSIDE the Music folder
     path** (siblings, e.g. `/Music/flac` + `/Music/opus`), never nested.
  2. **Near-deletion:** phone Music set send-only while its `/Music/flac`
     appeared empty (Syncthing `completion 0%`) → a send-only phone pushing
     "empty" to the receive-only workstation would have deleted the master.
     Paused before that could happen. (Read-only access made it moot, but the
     pattern is real once write access is granted.)

## Deferred — the FLAC-sync + ingest-move (next session)

The remaining piece: new phone downloads → workstation, and auto-freeing the
phone's FLAC (so the phone stores only Opus). The operator's intended design
(correct — the "ingest-move" pattern):

```
  phone /Music/flac ──push──▶ ws STAGING folder (NOT the master)
  ws ingest job: MOVE new flac → library/music (master)
  move = delete from staging → (two-way) → phone frees the FLAC
  ws library/music ──mirror──▶ music-opus ──▶ phone
```

Requirements / cautions before building:
- **Staging folder must be separate from the master** (`library/music`). The
  master must never be the thing the phone can delete from.
- Auto-freeing the phone's FLAC needs Syncthing **write** access on the phone
  (read-only can't delete).
- Resume the Music folder only after confirming the phone's folder paths don't
  overlap and `/Music/flac` actually holds the FLAC (reconcile the contaminated
  global first, or tear down + re-add the folder clean).

## Levers

```
  systemctl start music-mirror.service     # force a mirror sweep now
  journalctl -u music-mirror.service       # see the last run
  tonic-mirror --dry-run                    # what would transcode (hand-run)
  Syncthing API (workstation):  http://127.0.0.1:8384/rest  (apikey in
    ~/.config/syncthing/config.xml) — folders are runtime config, not nix.
```
