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

echo "=== BEFORE (staging) ==="; (cd "$staging" && find . -type f | sort)
echo "=== BEFORE (master) ===";  (cd "$master"  && find . -type f | sort)

# capture the master conflict file's pre-run content to prove it's untouched
conflict_master_before="$(cat "$master/Artist E/06 conflict.flac")"

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

# 7. re-run on a now-quiet staging → idempotent no-op (no crash, no new master
#    files). Remove the still-pending unstable/conflict files first so the second
#    run sees a stable-but-already-ingested set → all dedupe/no-op.
echo "=== RE-RUN (idempotency) ==="
rm -f "$staging/Artist B/~syncthing~02 transferring.flac.tmp" \
      "$staging/Artist B/.syncthing.03 oldtmp.flac.tmp" \
      "$staging/Artist B/02 transferring.flac" \
      "$staging/Artist B/03 oldtmp.flac" \
      "$staging/Artist C/04 fresh.flac"
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
