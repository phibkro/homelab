#!/usr/bin/env bash
# Fixture test for music-ingest.sh — proves each correctness guard on a synthetic
# /tmp staging+master tree. NEVER touches /mnt/media; everything lives in a temp
# dir wiped on exit. Tests encode WHY (the invariant), not WHAT (the impl).
#
# Run:  b3sum and coreutils on PATH (nix develop, or `nix shell nixpkgs#b3sum`):
#         bash modules/services/music-ingest.test.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/music-ingest.sh"

root="$(mktemp -d /tmp/music-ingest-test.XXXXXX)"
trap 'rm -rf "$root"' EXIT
staging="$root/staging"
library="$root/library"
master="$library/music"
mkdir -p "$staging" "$master"

# A FLAC is just bytes for this test — content identity is what the guards key
# on (blake3), not the audio. Distinct content → distinct hash.
mkflac() { mkdir -p "$(dirname "$1")"; printf '%s' "$2" >"$1"; }
# Backdate mtime past the stability window so the stable cases are eligible.
age() { touch -d '2 hours ago' "$1"; }

pass=0 fail=0
check() { # check <desc> <cond-cmd...>
  local desc="$1"; shift
  if "$@"; then echo "  ✓ $desc"; pass=$((pass + 1));
  else echo "  ✗ $desc"; fail=$((fail + 1)); fi
}

# ---------------------------------------------------------------------------
# Arrange the staging tree — one file per scenario.
# ---------------------------------------------------------------------------
# 1. complete stable FLAC → should ingest
mkflac "$staging/Artist A/Album/01 stable.flac" "stable-content-A"; age "$staging/Artist A/Album/01 stable.flac"
# 2. file WITH a syncthing temp sibling (new pattern) → leave
mkflac "$staging/Artist B/02 transferring.flac" "mid-transfer"; age "$staging/Artist B/02 transferring.flac"
:>"$staging/Artist B/~syncthing~02 transferring.flac.tmp"
# 2b. file WITH a syncthing temp sibling (old pattern) → leave
mkflac "$staging/Artist B/03 oldtmp.flac" "mid-transfer-old"; age "$staging/Artist B/03 oldtmp.flac"
:>"$staging/Artist B/.syncthing.03 oldtmp.flac.tmp"
# 3. fresh mtime INSIDE the stability window → leave (no age call)
mkflac "$staging/Artist C/04 fresh.flac" "just-landed"
# 4. duplicate — identical content already in master → free from staging
mkflac "$master/Artist D/05 dup.flac" "dup-content"
mkflac "$staging/Artist D/05 dup.flac" "dup-content"; age "$staging/Artist D/05 dup.flac"
# 5. conflict — same relpath, DIFFERENT content → quarantine, master intact
mkflac "$master/Artist E/06 conflict.flac" "MASTER-original"
mkflac "$staging/Artist E/06 conflict.flac" "STAGING-different"; age "$staging/Artist E/06 conflict.flac"
# 6. nested subdir → structure preserved
mkflac "$staging/Artist F/Album X/Disc 1/07 nested.flac" "nested-content"; age "$staging/Artist F/Album X/Disc 1/07 nested.flac"

# --- ART: rides the EXACT same guards as FLAC (file-type filter generalized) --
# `mkflac` writes arbitrary bytes — fine for art too; the guards key on
# content blake3, not audio. Extensions covered: .jpg .jpeg .png .webp,
# case-insensitive, non-hidden.
# 7. complete stable art (folder.jpg) alongside its album → ingest
mkflac "$staging/Artist A/Album/folder.jpg" "JPEG-cover-A"; age "$staging/Artist A/Album/folder.jpg"
# 7b. mixed-case extension (Cover.PNG) → ingest (case-insensitive match)
mkflac "$staging/Artist F/Album X/Cover.PNG" "PNG-cover-F"; age "$staging/Artist F/Album X/Cover.PNG"
# 7c. .webp + .jpeg variants → ingest (full extension set)
mkflac "$staging/Artist G/back.webp" "WEBP-back-G"; age "$staging/Artist G/back.webp"
mkflac "$staging/Artist G/front.jpeg" "JPEG-front-G"; age "$staging/Artist G/front.jpeg"
# 8. art WITH a syncthing temp sibling → leave (mid-sync, same stable guard)
mkflac "$staging/Artist H/cover.png" "art-mid-transfer"; age "$staging/Artist H/cover.png"
:>"$staging/Artist H/~syncthing~cover.png.tmp"
# 9. art fresh mtime INSIDE the stability window → leave
mkflac "$staging/Artist I/cover.jpg" "art-just-landed"
# 10. duplicate art — identical content already in master → free from staging
mkflac "$master/Artist J/folder.jpg" "art-dup"
mkflac "$staging/Artist J/folder.jpg" "art-dup"; age "$staging/Artist J/folder.jpg"
# 11. conflict art — same relpath, DIFFERENT content → quarantine, master intact
mkflac "$master/Artist K/folder.jpg" "ART-MASTER-original"
mkflac "$staging/Artist K/folder.jpg" "ART-STAGING-different"; age "$staging/Artist K/folder.jpg"
# 12. hidden art (.secret.jpg) → NEVER ingested (non-hidden invariant)
mkflac "$staging/Artist L/.secret.jpg" "hidden-art"; age "$staging/Artist L/.secret.jpg"
# 12b. non-art non-FLAC (.txt/.log/.cue) → left alone in staging (out of scope)
mkflac "$staging/Artist L/notes.txt" "tracklist"; age "$staging/Artist L/notes.txt"

echo "=== BEFORE (staging) ==="; (cd "$staging" && find . -type f | sort)
echo "=== BEFORE (master) ===";  (cd "$master"  && find . -type f | sort)

# capture the master conflict files' pre-run content to prove they're untouched
conflict_master_before="$(cat "$master/Artist E/06 conflict.flac")"
art_conflict_master_before="$(cat "$master/Artist K/folder.jpg")"

# ---------------------------------------------------------------------------
# Act
# ---------------------------------------------------------------------------
echo "=== RUN ==="
set +e
MUSIC_INGEST_STAGING="$staging" \
MUSIC_INGEST_LIBRARY="$library" \
MUSIC_INGEST_STABILITY_SECONDS=60 \
  bash "$script"
rc=$?
set -e
echo "  (exit $rc — nonzero-on-conflict is by design)"

echo "=== AFTER (staging) ==="; (cd "$staging" && find . -type f | sort)
echo "=== AFTER (master) ===";  (cd "$master"  && find . -type f | sort)

# ---------------------------------------------------------------------------
# Assert — each check is a business rule; it fails when the rule is violated.
# ---------------------------------------------------------------------------
echo "=== ASSERT ==="
# 1. stable → moved to master, gone from staging
check "stable FLAC ingested into master"        test -f "$master/Artist A/Album/01 stable.flac"
check "stable FLAC removed from staging"         test ! -e "$staging/Artist A/Album/01 stable.flac"

# 2. syncthing temp sibling (both patterns) → left untouched in staging
check "new-pattern temp-sibling file left in staging"  test -f "$staging/Artist B/02 transferring.flac"
check "old-pattern temp-sibling file left in staging"  test -f "$staging/Artist B/03 oldtmp.flac"
check "temp-sibling file NOT in master"                test ! -e "$master/Artist B/02 transferring.flac"

# 3. inside stability window → left in staging
check "fresh (mid-write) file left in staging"   test -f "$staging/Artist C/04 fresh.flac"
check "fresh file NOT in master"                 test ! -e "$master/Artist C/04 fresh.flac"

# 4. duplicate → removed from staging, master byte-identical
check "duplicate removed from staging (phone freed)"  test ! -e "$staging/Artist D/05 dup.flac"
check "duplicate still present in master"             test -f "$master/Artist D/05 dup.flac"
check "master duplicate content unchanged" \
  bash -c '[ "$(cat "'"$master"'/Artist D/05 dup.flac")" = "dup-content" ]'

# 5. conflict → quarantined, master ORIGINAL intact, not in master's path overwritten
check "conflict master original byte-for-byte intact" \
  bash -c '[ "$(cat "'"$master"'/Artist E/06 conflict.flac")" = "'"$conflict_master_before"'" ]'
check "conflict staging file moved to .conflicts" \
  test -f "$staging/.conflicts/Artist E/06 conflict.flac"
check "conflict staging file gone from original staging path" \
  test ! -e "$staging/Artist E/06 conflict.flac"
check "conflict surfaced via nonzero exit code" \
  bash -c '[ "'"$rc"'" -eq 3 ]'

# 6. nested subdir → structure preserved in master, gone from staging
check "nested subdir structure preserved in master" \
  test -f "$master/Artist F/Album X/Disc 1/07 nested.flac"
check "nested file removed from staging" \
  test ! -e "$staging/Artist F/Album X/Disc 1/07 nested.flac"
check "nested content correct" \
  bash -c '[ "$(cat "'"$master"'/Artist F/Album X/Disc 1/07 nested.flac")" = "nested-content" ]'

# --- ART assertions: art rides the SAME guards as FLAC -----------------------
# 7. stable art ingested into master alongside its album, gone from staging
check "stable art (folder.jpg) ingested into master"  test -f "$master/Artist A/Album/folder.jpg"
check "stable art removed from staging"               test ! -e "$staging/Artist A/Album/folder.jpg"
check "ingested art content correct" \
  bash -c '[ "$(cat "'"$master"'/Artist A/Album/folder.jpg")" = "JPEG-cover-A" ]'
# 7b. mixed-case extension matched (Cover.PNG)
check "mixed-case art (Cover.PNG) ingested"           test -f "$master/Artist F/Album X/Cover.PNG"
check "mixed-case art removed from staging"           test ! -e "$staging/Artist F/Album X/Cover.PNG"
# 7c. .webp + .jpeg variants ingested (full extension set)
check ".webp art ingested"                            test -f "$master/Artist G/back.webp"
check ".jpeg art ingested"                            test -f "$master/Artist G/front.jpeg"

# 8. art with syncthing temp sibling → left in staging, NOT in master
check "art mid-sync (temp sibling) left in staging"   test -f "$staging/Artist H/cover.png"
check "art mid-sync NOT in master"                    test ! -e "$master/Artist H/cover.png"

# 9. fresh art inside stability window → left in staging
check "fresh art (mid-write) left in staging"         test -f "$staging/Artist I/cover.jpg"
check "fresh art NOT in master"                       test ! -e "$master/Artist I/cover.jpg"

# 10. duplicate art → removed from staging, master byte-identical
check "duplicate art removed from staging"            test ! -e "$staging/Artist J/folder.jpg"
check "duplicate art still present in master"         test -f "$master/Artist J/folder.jpg"
check "master duplicate art content unchanged" \
  bash -c '[ "$(cat "'"$master"'/Artist J/folder.jpg")" = "art-dup" ]'

# 11. conflict art → quarantined to .conflicts, master ORIGINAL byte-intact
check "art conflict master original byte-for-byte intact" \
  bash -c '[ "$(cat "'"$master"'/Artist K/folder.jpg")" = "'"$art_conflict_master_before"'" ]'
check "art conflict staging file moved to .conflicts" \
  test -f "$staging/.conflicts/Artist K/folder.jpg"
check "art conflict staging file gone from original path" \
  test ! -e "$staging/Artist K/folder.jpg"

# 12. hidden art (.secret.jpg) → NEVER ingested (non-hidden invariant), left alone
check "hidden art (.secret.jpg) NOT ingested into master"  test ! -e "$master/Artist L/.secret.jpg"
check "hidden art left untouched in staging"               test -f "$staging/Artist L/.secret.jpg"
# 12b. non-art non-FLAC (.txt) → left alone in staging, not in master
check "non-art .txt NOT ingested into master"         test ! -e "$master/Artist L/notes.txt"
check "non-art .txt left untouched in staging"        test -f "$staging/Artist L/notes.txt"

# 7. re-run on a now-quiet staging → idempotent no-op (no crash, no new master
#    files). Remove the still-pending unstable/conflict files first so the second
#    run sees a stable-but-already-ingested set → all dedupe/no-op.
echo "=== RE-RUN (idempotency) ==="
rm -f "$staging/Artist B/~syncthing~02 transferring.flac.tmp" \
      "$staging/Artist B/.syncthing.03 oldtmp.flac.tmp" \
      "$staging/Artist B/02 transferring.flac" \
      "$staging/Artist B/03 oldtmp.flac" \
      "$staging/Artist C/04 fresh.flac" \
      "$staging/Artist H/~syncthing~cover.png.tmp" \
      "$staging/Artist H/cover.png" \
      "$staging/Artist I/cover.jpg"
master_snapshot_before="$(cd "$master" && find . -type f -exec b3sum --no-names {} \; | sort)"
set +e
MUSIC_INGEST_STAGING="$staging" MUSIC_INGEST_LIBRARY="$library" \
  MUSIC_INGEST_STABILITY_SECONDS=60 bash "$script" >/dev/null 2>&1
rerun_rc=$?
set -e
master_snapshot_after="$(cd "$master" && find . -type f -exec b3sum --no-names {} \; | sort)"
check "re-run leaves master byte-identical (idempotent)" \
  bash -c '[ "'"$master_snapshot_before"'" = "'"$master_snapshot_after"'" ]'
# re-run still has the unresolved conflict in staging/.conflicts (NOT re-scanned)
# but no NEW conflicts arise, and the previously-ingested files are gone → rc 0.
check "re-run is a clean no-op (rc 0, conflicts quarantine not re-scanned)" \
  bash -c '[ "'"$rerun_rc"'" -eq 0 ]'

echo
echo "=== RESULT: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
