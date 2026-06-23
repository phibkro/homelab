#!/usr/bin/env bash
# music-ingest — MOVE complete, stable FLAC files from a transient Syncthing
# staging dir into the irreplaceable master music library, then delete the
# staging copy (a separate Syncthing sendreceive folder propagates that delete
# to the phone, freeing the phone's FLAC). The master is populated by a LOCAL
# fs operation; the phone is never linked to it.
#
# Invariants this script enforces (see the fixture test for the WHY of each):
#   1. stable-file guard — ingest only if NO sibling Syncthing temp file exists
#      AND mtime is older than the stability window (not mid-write).
#   2. dedupe/conflict by relpath against the master, content-keyed on blake3:
#        same relpath + same content  → delete from staging ("deduped").
#        same relpath + diff content  → move staging file to <staging>/.conflicts/
#                                        (LOUD); master original NEVER clobbered.
#        not in master                → ingest.
#   3. crash-safe move — copy to a temp file inside the master dir, fsync, atomic
#      rename to the final path, THEN unlink staging. A crash mid-move never
#      leaves a half-written file at the master's final path.
#   4. relative subpaths (artist/album) preserved. Idempotent + re-runnable.
#
# Config is explicit at the boundary — the caller (nix unit OR the test) declares
# every path/window; this script guesses nothing.
#
#   MUSIC_INGEST_STAGING            required  transient Syncthing staging dir
#   MUSIC_INGEST_LIBRARY            required  master library root (holds music/)
#   MUSIC_INGEST_STABILITY_SECONDS  default 60   mtime-age stability window
#   MUSIC_INGEST_GLOB               default *.flac   files considered for ingest
set -euo pipefail

: "${MUSIC_INGEST_STAGING:?MUSIC_INGEST_STAGING (the Syncthing staging dir) is required}"
: "${MUSIC_INGEST_LIBRARY:?MUSIC_INGEST_LIBRARY (the master library root) is required}"
stability="${MUSIC_INGEST_STABILITY_SECONDS:-60}"
glob="${MUSIC_INGEST_GLOB:-*.flac}"

staging="$MUSIC_INGEST_STAGING"
# music/ under the library root — same layout the FLAC→Opus mirror reads from
# (TONIC_MUSIC_ROOT = ${library}/music). Single source of truth for the layout.
master="$MUSIC_INGEST_LIBRARY/music"
conflicts="$staging/.conflicts"

if [ ! -d "$staging" ]; then
  echo "music-ingest: staging dir does not exist: $staging" >&2
  exit 1
fi
mkdir -p "$master"

now="$(date +%s)"
ingested=0 deduped=0 conflicted=0 unstable=0

# blake3 of a file, stdout = the 64-hex digest only.
b3() { b3sum --no-names "$1"; }

# A Syncthing temp sibling for <dir>/<base> exists if EITHER pattern Syncthing
# uses is present. Both are checked — Syncthing changed the convention across
# versions (`.syncthing.<name>.tmp` old, `~syncthing~<name>.tmp` newer), and a
# file mid-transfer under either name means "not complete, leave it".
has_syncthing_tmp() {
  local dir="$1" base="$2"
  [ -e "$dir/.syncthing.$base.tmp" ] || [ -e "$dir/~syncthing~$base.tmp" ]
}

# Find every candidate FLAC under staging, skipping the .conflicts quarantine
# and any Syncthing temp files themselves. -print0 / read -d '' to survive
# spaces + unicode in artist/album/track names.
while IFS= read -r -d '' src; do
  rel="${src#"$staging"/}"
  base="$(basename "$src")"
  dir="$(dirname "$src")"

  # --- guard 1: stability -------------------------------------------------
  if has_syncthing_tmp "$dir" "$base"; then
    echo "music-ingest: unstable (syncthing temp sibling) — leaving: $rel" >&2
    unstable=$((unstable + 1))
    continue
  fi
  mtime="$(stat -c %Y "$src")"
  age=$((now - mtime))
  if [ "$age" -lt "$stability" ]; then
    echo "music-ingest: unstable (mtime ${age}s < ${stability}s window) — leaving: $rel" >&2
    unstable=$((unstable + 1))
    continue
  fi

  dst="$master/$rel"

  # --- guard 2: dedupe / collision ---------------------------------------
  if [ -e "$dst" ]; then
    if [ "$(b3 "$src")" = "$(b3 "$dst")" ]; then
      # Already ingested, identical content → free the phone, master untouched.
      rm -f -- "$src"
      echo "music-ingest: deduped (already in master, identical) — freed: $rel"
      deduped=$((deduped + 1))
      continue
    else
      # Same path, DIFFERENT content → never clobber the irreplaceable master.
      # Quarantine the staging file; the operator resolves by hand.
      qdst="$conflicts/$rel"
      mkdir -p "$(dirname "$qdst")"
      mv -f -- "$src" "$qdst"
      echo "music-ingest: CONFLICT — staging differs from master at '$rel'." >&2
      echo "music-ingest:   master kept intact; staging copy moved to: .conflicts/$rel" >&2
      conflicted=$((conflicted + 1))
      continue
    fi
  fi

  # --- guard 3: crash-safe move ------------------------------------------
  # Temp file INSIDE the master dir (same filesystem → rename is atomic).
  mkdir -p "$(dirname "$dst")"
  tmp="$(mktemp "$(dirname "$dst")/.music-ingest.XXXXXX")"
  # cp then fsync the file AND its parent dir before the atomic rename, so a
  # crash can never expose a partially-written file at the final path.
  cp -- "$src" "$tmp"
  sync -- "$tmp"
  mv -f -- "$tmp" "$dst"
  sync -- "$(dirname "$dst")"
  # Only NOW remove the staging source — the master copy is durable.
  rm -f -- "$src"
  echo "music-ingest: ingested → $rel"
  ingested=$((ingested + 1))
done < <(find "$staging" -type f -name "$glob" -not -path "$conflicts/*" -print0)

echo "music-ingest: done — ingested=$ingested deduped=$deduped conflicted=$conflicted unstable=$unstable"
# Conflicts are a loud-but-non-fatal operator-action signal; surface in the exit
# code so a wrapping unit / OnFailure alert fires without losing the other work.
[ "$conflicted" -eq 0 ] || exit 3
