#!/usr/bin/env bash
# music-ingest — atomically claim stable files from a Syncthing staging tree,
# then publish the owned bytes into the canonical music tree.
#
# Provenance: the eligibility, stability, BLAKE3, dedupe, conflict, and
# publication behavior is carried forward from Plan 009
# (docs/archive/legacy-plans/009-claim-music-before-ingest.md) and the archived
# compiler-prototype acceptance report
# (docs/archive/reports/2026-09-06-music-ingest-compiler-prototype/README.md).
# The durable claim, no-clobber paths, lock, and recovery rules below close
# the prototype's replacement/delete race.
#
# The claim is durable state. A claim is removed only after a durable master
# publication (or after an identical destination is verified). If the process
# is interrupted while copying, the claim remains under MUSIC_INGEST_INFLIGHT
# and is retried on the next invocation.
#
# Required environment:
#   MUSIC_INGEST_STAGING   Syncthing-managed source tree
#   MUSIC_INGEST_MASTER    canonical destination tree
#   MUSIC_INGEST_INFLIGHT   durable claim tree, same filesystem as staging
#
# Optional environment:
#   MUSIC_INGEST_STABILITY_SECONDS (default 60)
#   MUSIC_INGEST_EXTENSIONS (default "flac jpg jpeg png webp")
#
# Runtime assumptions:
#   * Syncthing and other same-user writers replace files atomically. A writer
#     that mutates a file in place after the age check is outside this adapter's
#     claim model; the copied bytes are still verified against the claimed inode.
#   * A concurrent writer may create a new source or destination path. Source
#     replacement is safe because this adapter deletes only its claimed inode.
#     Destination publication is no-clobber; a concurrent destination is then
#     handled as a duplicate or conflict.
#   * flock releases the invocation lock when the process exits. This serializes
#     invocations of this adapter, but does not provide a general filesystem
#     transaction or a claim against writers that bypass atomic rename.
#   * The three configured trees are trusted directory namespaces: a writer
#     must not swap parent symlinks during this adapter's pre/post checks. The
#     checks reject existing escapes, but shell/coreutils cannot make a hostile
#     directory mutation transactional.
set -euo pipefail

: "${MUSIC_INGEST_STAGING:?MUSIC_INGEST_STAGING is required}"
: "${MUSIC_INGEST_MASTER:?MUSIC_INGEST_MASTER is required}"
: "${MUSIC_INGEST_INFLIGHT:?MUSIC_INGEST_INFLIGHT is required}"

staging="${MUSIC_INGEST_STAGING%/}"
master="${MUSIC_INGEST_MASTER%/}"
inflight="${MUSIC_INGEST_INFLIGHT%/}"
stability="${MUSIC_INGEST_STABILITY_SECONDS:-60}"
extensions="${MUSIC_INGEST_EXTENSIONS:-flac jpg jpeg png webp}"

if [ -z "$staging" ] || [ -z "$master" ] || [ -z "$inflight" ]; then
  echo "music-ingest: paths must not be empty" >&2
  exit 1
fi

# The compiler should enforce these relationships declaratively. Keep the
# runtime guard too: normalize existing symlinks and dot segments before the
# check so a lexical spelling cannot make the scanner see its own durable state
# or make a phone-controlled tree overlap the canonical library.
if ! staging="$(realpath -m -- "$staging")" \
  || ! master="$(realpath -m -- "$master")" \
  || ! inflight="$(realpath -m -- "$inflight")"; then
  echo "music-ingest: cannot normalize staging, master, and inflight paths" >&2
  exit 1
fi
path_contains() {
  local parent="$1" child="$2"
  if [ "$parent" = "/" ]; then
    [ "$child" != "/" ] && [[ "$child" = /* ]] && return 0
    return 1
  fi
  case "$child" in
    "$parent"/*) return 0 ;;
    *) return 1 ;;
  esac
}
path_within_or_equal() {
  local parent="$1" child="$2"
  [ "$parent" = "$child" ] || path_contains "$parent" "$child"
}
if [ "$staging" = "$master" ] || [ "$staging" = "$inflight" ] || [ "$master" = "$inflight" ] \
  || path_contains "$staging" "$master" || path_contains "$staging" "$inflight" \
  || path_contains "$master" "$staging" || path_contains "$master" "$inflight" \
  || path_contains "$inflight" "$staging" || path_contains "$inflight" "$master"; then
  echo "music-ingest: staging, master, and inflight paths must be distinct and disjoint" >&2
  exit 1
fi
if [ ! -d "$staging" ]; then
  echo "music-ingest: staging dir does not exist: $staging" >&2
  exit 1
fi

# mkdir is intentionally done before the device check: the caller must choose
# an existing or creatable inflight directory, and no source is moved until the
# two device IDs have been compared.
mkdir -p -- "$master" "$inflight"
if [ ! -d "$master" ] || [ ! -d "$inflight" ]; then
  echo "music-ingest: master and inflight must be directories" >&2
  exit 1
fi

staging_device="$(stat -c %d -- "$staging")"
inflight_device="$(stat -c %d -- "$inflight")"
if [ "$staging_device" != "$inflight_device" ]; then
  echo "music-ingest: staging and inflight must share a filesystem (devices $staging_device and $inflight_device)" >&2
  exit 1
fi
master_device="$(stat -c %d -- "$master")"

# Locking is part of the adapter contract. util-linux's flock is intentionally
# used instead of a removable mkdir lock: the kernel releases this lock after a
# crash, while claims remain durable for recovery.
lock_path="$inflight/.music-ingest.lock"
exec 9>"$lock_path"
flock -x 9

file_mode="$(printf '%o' $((0666 & ~$(umask))))"
now="$(date +%s)"
ingested=0
deduped=0
conflicted=0
unstable=0
failed=0

# The trap only removes ephemeral enumeration lists and the master-local copy
# temp. It never removes a claim or a staging path.
tmp_path=""
list_path=""
stale_list_path=""
cleanup() {
  if [ -n "$tmp_path" ]; then
    rm -f -- "$tmp_path"
    tmp_path=""
  fi
  if [ -n "$list_path" ]; then
    rm -f -- "$list_path"
    list_path=""
  fi
  if [ -n "$stale_list_path" ]; then
    rm -f -- "$stale_list_path"
    stale_list_path=""
  fi
}
trap cleanup EXIT INT TERM

discard_tmp() {
  if [ -z "$tmp_path" ]; then
    return 0
  fi
  if rm -f -- "$tmp_path"; then
    tmp_path=""
    return 0
  fi
  echo "music-ingest: cannot remove destination temp; retaining it for cleanup: $tmp_path" >&2
  return 1
}

b3() {
  b3sum --no-names -- "$1"
}

is_hidden_rel() {
  case "$1" in
    .*|*/.*) return 0 ;;
    *) return 1 ;;
  esac
}

is_eligible() {
  local path="$1" suffix ext
  case "$path" in
    *.*) suffix="${path##*.}" ;;
    *) return 1 ;;
  esac
  suffix="${suffix,,}"
  for ext in $extensions; do
    [ "$suffix" = "${ext,,}" ] && return 0
  done
  return 1
}

has_syncthing_tmp() {
  local dir="$1" base="$2"
  [ -e "$dir/.syncthing.$base.tmp" ] || [ -e "$dir/~syncthing~$base.tmp" ]
}

claim_owner_marker() {
  printf '%s.owner' "$1"
}

# An owner marker distinguishes an adapter-created durable claim from an
# operator-created collision. It records the source device, inode, and mtime
# seen by the stability guard; a changed, still-young claim is held for a later
# sweep.
claim_marker_metadata() {
  local marker version marker_device marker_inode marker_mtime
  marker="$(claim_owner_marker "$1")"
  [ -f "$marker" ] || return 1
  {
    IFS= read -r version
    IFS= read -r marker_device
    IFS= read -r marker_inode
    IFS= read -r marker_mtime
  } <"$marker" || return 1
  [ "$version" = "music-ingest-v1" ] || return 1
  [[ "$marker_device" =~ ^[0-9]+$ ]] || return 1
  [[ "$marker_inode" =~ ^[0-9]+$ ]] || return 1
  [[ "$marker_mtime" =~ ^[0-9]+$ ]] || return 1
  printf '%s %s %s\n' "$marker_device" "$marker_inode" "$marker_mtime"
}

claim_is_owned() {
  claim_marker_metadata "$1" >/dev/null
}

remove_claim() {
  local claim="$1" marker
  marker="$(claim_owner_marker "$claim")"
  # Remove the claim before its marker. If interrupted between these two
  # operations, a stale marker is harmless; if interrupted before claim
  # removal, the marker keeps the claim recognizable as owned recovery state.
  if ! rm -f -- "$claim"; then
    return 1
  fi
  if [ -e "$marker" ] && ! rm -f -- "$marker"; then
    return 1
  fi
  sync -- "$(dirname "$claim")"
}

# Find's output is materialized so traversal errors cannot be hidden by a
# process-substitution pipeline. Lists contain NUL-separated absolute paths.
# The supplied root itself may have a hidden basename (the production inflight
# binding is commonly `.music-ingest-inflight`), so hidden filtering is relative
# to that root: prune hidden descendants, but inspect files directly below a
# hidden root just like files below a visible root.
collect_files() {
  local root="$1" output="$2"
  if ! find "$root" -mindepth 1 \
    \( -type d -name '.*' -prune \) -o \
    \( -type f "${name_filter[@]}" ! -name '.*' -print0 \) >"$output"; then
    echo "music-ingest: failed to scan: $root" >&2
    return 1
  fi
}

collect_stale_temps() {
  local root="$1" output="$2"
  if ! find "$root" -type f -name '.music-ingest.*' -print0 >"$output"; then
    echo "music-ingest: failed to scan destination temps: $root" >&2
    return 1
  fi
}

collect_owner_markers() {
  local root="$1" output="$2"
  if ! find "$root" -type f -name '*.owner' -print0 >"$output"; then
    echo "music-ingest: failed to scan claim markers: $root" >&2
    return 1
  fi
}

quarantine_claim() {
  local claim="$1" rel="$2" digest="$3" qdst candidate marker qdir qdir_real
  qdst="$staging/.conflicts/$rel"
  qdir="$(dirname "$qdst")"
  if ! qdir_real="$(realpath -m -- "$qdir")" || ! path_within_or_equal "$staging" "$qdir_real"; then
    echo "music-ingest: conflict quarantine escapes staging root; retaining claim: $rel" >&2
    return 1
  fi
  if ! mkdir -p -- "$qdir"; then
    echo "music-ingest: cannot create conflict quarantine; retaining claim: $rel" >&2
    return 1
  fi
  if ! qdir_real="$(realpath -m -- "$qdir")" || ! path_within_or_equal "$staging" "$qdir_real"; then
    echo "music-ingest: conflict quarantine changed outside staging root; retaining claim: $rel" >&2
    return 1
  fi

  # Keep the historical readable conflict path for the first collision. If an
  # earlier conflict already occupies it, use a content-keyed suffix. A final
  # no-clobber move plus a claim-exists check handles a concurrent quarantine
  # writer without replacing its evidence.
  if [ -e "$qdst" ]; then
    candidate="${qdst}.${digest}"
    if [ -e "$candidate" ]; then
      echo "music-ingest: conflict quarantine already exists; retaining claim: $rel" >&2
      return 1
    fi
    qdst="$candidate"
  fi
  if ! mv -nT -- "$claim" "$qdst"; then
    echo "music-ingest: failed to quarantine claim; retaining claim: $rel" >&2
    return 1
  fi
  if [ -e "$claim" ]; then
    echo "music-ingest: quarantine target appeared concurrently; retaining claim: $rel" >&2
    return 1
  fi
  # The quarantine rename is the ownership handoff. Make it durable before
  # releasing the marker that tells recovery this claim is adapter-owned.
  if ! sync -- "$(dirname "$qdst")"; then
    echo "music-ingest: quarantine move is not durable; recovery will inspect: $rel" >&2
    return 1
  fi
  marker="$(claim_owner_marker "$claim")"
  if [ -e "$marker" ] && ! rm -f -- "$marker"; then
    echo "music-ingest: quarantined claim but could not remove owner marker: $rel" >&2
    return 1
  fi
  if ! sync -- "$(dirname "$claim")"; then
    echo "music-ingest: quarantine marker removal is not durable; recovery will inspect: $rel" >&2
    return 1
  fi
  echo "music-ingest: CONFLICT — master kept intact; claim moved to: ${qdst#"$staging"/}" >&2
  return 0
}

process_claim() {
  local claim="$1" rel="$2" dst dst_dir claim_digest dst_digest parent_device
  local marker_metadata marker_device marker_inode marker_mtime claim_device claim_inode claim_mtime claim_age
  dst="$master/$rel"
  dst_dir="$(dirname "$dst")"

  if [ -n "$tmp_path" ]; then
    echo "music-ingest: previous destination temp could not be cleaned; retaining claim: $rel" >&2
    return 1
  fi

  if [ -L "$claim" ] || [ ! -f "$claim" ]; then
    echo "music-ingest: claim disappeared before processing; recovery required: $rel" >&2
    return 1
  fi

  # Claims made by this adapter carry the mtime observed before their atomic
  # rename. If a writer replaced the staging inode in the check/rename window,
  # the claimed inode is rechecked here and held until its own stability window
  # has elapsed. Manual/recovered claims without a marker are processed as
  # already-owned recovery state.
  if marker_metadata="$(claim_marker_metadata "$claim")"; then
    read -r marker_device marker_inode marker_mtime <<<"$marker_metadata"
    claim_stat=""
    if ! claim_stat="$(stat -c '%d %i %Y' -- "$claim")"; then
      echo "music-ingest: cannot revalidate claim mtime; retaining claim: $rel" >&2
      return 1
    fi
    read -r claim_device claim_inode claim_mtime <<<"$claim_stat"
    if [ "$claim_device" != "$marker_device" ] || [ "$claim_inode" != "$marker_inode" ] || [ "$claim_mtime" != "$marker_mtime" ]; then
      claim_age=$((now - claim_mtime))
      if [ "$claim_age" -lt "$stability" ]; then
        echo "music-ingest: unstable claim (mtime ${claim_age}s < ${stability}s window) — leaving: $rel" >&2
        unstable=$((unstable + 1))
        return 0
      fi
    fi
  fi

  # Validate the destination parent before reading an existing destination as
  # well as before creating a new one. Otherwise an internal parent symlink
  # could make the dedupe/conflict checksum follow a path outside master.
  if ! dst_dir="$(realpath -m -- "$dst_dir")" || ! path_within_or_equal "$master" "$dst_dir"; then
    echo "music-ingest: destination parent escapes master root; retaining claim: $rel" >&2
    return 1
  fi

  claim_digest="$(b3 "$claim")" || {
    echo "music-ingest: cannot checksum claim; retaining it: $rel" >&2
    return 1
  }

  if [ -e "$dst" ]; then
    if [ -L "$dst" ] || [ ! -f "$dst" ]; then
      echo "music-ingest: destination is not a regular file; retaining claim: $rel" >&2
      return 1
    fi
    dst_digest="$(b3 "$dst")" || {
      echo "music-ingest: cannot checksum destination; retaining claim: $rel" >&2
      return 1
    }
    if [ "$claim_digest" = "$dst_digest" ]; then
      if ! sync -- "$dst_dir"; then
        echo "music-ingest: identical destination is not durable; retaining claim: $rel" >&2
        return 1
      fi
      if ! remove_claim "$claim"; then
        echo "music-ingest: identical destination verified but claim removal failed: $rel" >&2
        return 1
      fi
      echo "music-ingest: deduped (already in master, identical) — freed claim: $rel"
      deduped=$((deduped + 1))
      return 0
    fi
    if quarantine_claim "$claim" "$rel" "$claim_digest"; then
      conflicted=$((conflicted + 1))
      return 0
    fi
    return 1
  fi

  if ! mkdir -p -- "$dst_dir"; then
    echo "music-ingest: cannot create destination parent; retaining claim: $rel" >&2
    return 1
  fi
  if ! dst_dir="$(realpath -m -- "$dst_dir")" || ! path_within_or_equal "$master" "$dst_dir"; then
    echo "music-ingest: destination parent changed outside master root; retaining claim: $rel" >&2
    return 1
  fi
  parent_device="$(stat -c %d -- "$dst_dir")"
  if [ "$parent_device" != "$master_device" ]; then
    echo "music-ingest: destination parent is on a different filesystem; retaining claim: $rel" >&2
    return 1
  fi

  tmp_path="$(mktemp "$dst_dir/.music-ingest.XXXXXX")" || {
    echo "music-ingest: cannot create destination temp; retaining claim: $rel" >&2
    return 1
  }
  if ! cp -- "$claim" "$tmp_path"; then
    discard_tmp || true
    echo "music-ingest: copy interrupted; retaining claim: $rel" >&2
    return 1
  fi
  if ! chmod "$file_mode" -- "$tmp_path"; then
    discard_tmp || true
    echo "music-ingest: cannot set destination mode; retaining claim: $rel" >&2
    return 1
  fi
  if ! sync -- "$tmp_path"; then
    discard_tmp || true
    echo "music-ingest: cannot sync destination temp; retaining claim: $rel" >&2
    return 1
  fi
  if [ "$(b3 "$tmp_path")" != "$claim_digest" ]; then
    discard_tmp || true
    echo "music-ingest: copied bytes differ from claim; retaining claim: $rel" >&2
    return 1
  fi

  # mv -n is essential here: a concurrent producer may have populated the
  # canonical path after the initial check. Never replace that producer's file.
  if ! mv -nT -- "$tmp_path" "$dst"; then
    discard_tmp || true
    echo "music-ingest: destination publication failed; retaining claim: $rel" >&2
    return 1
  fi
  if [ -e "$tmp_path" ]; then
    # Destination appeared between the check and no-clobber rename. Reconcile
    # without deleting either producer's bytes.
    dst_digest=""
    if [ -f "$dst" ] && [ ! -L "$dst" ]; then
      if ! dst_digest="$(b3 "$dst")"; then
        discard_tmp || true
        echo "music-ingest: cannot checksum raced destination; retaining claim: $rel" >&2
        return 1
      fi
    fi
    if [ "$dst_digest" = "$claim_digest" ]; then
      if ! rm -f -- "$tmp_path"; then
        echo "music-ingest: cannot remove duplicate temp; retaining claim: $rel" >&2
        return 1
      fi
      tmp_path=""
      if ! sync -- "$dst_dir"; then
        echo "music-ingest: raced identical destination is not durable; retaining claim: $rel" >&2
        return 1
      fi
      if ! remove_claim "$claim"; then
        echo "music-ingest: duplicate destination won race but claim removal failed: $rel" >&2
        return 1
      fi
      echo "music-ingest: deduped (destination appeared with identical content) — freed claim: $rel"
      deduped=$((deduped + 1))
      return 0
    fi
    if ! rm -f -- "$tmp_path"; then
      echo "music-ingest: cannot remove raced temp; retaining claim: $rel" >&2
      return 1
    fi
    tmp_path=""
    if quarantine_claim "$claim" "$rel" "$claim_digest"; then
      conflicted=$((conflicted + 1))
      return 0
    fi
    return 1
  fi

  # Publication is durable before ownership is released. The claim path is
  # the only input this function is allowed to delete.
  tmp_path=""
  if ! sync -- "$dst_dir"; then
    echo "music-ingest: master publication is not durable; retaining claim: $rel" >&2
    return 1
  fi
  if ! remove_claim "$claim"; then
    echo "music-ingest: master published but claim removal failed; recovery will dedupe: $rel" >&2
    return 1
  fi
  echo "music-ingest: ingested → $rel"
  ingested=$((ingested + 1))
  return 0
}

# Build the find expression once. -iname preserves the case-insensitive
# extension contract while the hidden-path filter applies to every branch.
name_filter=()
for ext in $extensions; do
  name_filter+=(-o -iname "*.$ext")
done
if [ "${#name_filter[@]}" -eq 0 ]; then
  echo "music-ingest: MUSIC_INGEST_EXTENSIONS must contain at least one extension" >&2
  exit 1
fi
name_filter[0]='('
name_filter+=(')')

# A SIGKILL can leave a master-local copy temp behind while its claim remains
# durable. The temp is never the only copy: the claim is fsynced before copy,
# and publication removes the temp by rename. Remove only this adapter's
# reserved temp namespace before recovery, then fsync each affected parent.
stale_list_path="$(mktemp "${TMPDIR:-/tmp}/music-ingest-stale.XXXXXX")"
if collect_stale_temps "$master" "$stale_list_path"; then
  while IFS= read -r -d '' stale_temp; do
    if ! rm -f -- "$stale_temp"; then
      echo "music-ingest: cannot remove stale destination temp: $stale_temp" >&2
      failed=1
      continue
    fi
    if ! sync -- "$(dirname "$stale_temp")"; then
      echo "music-ingest: stale destination temp removal is not durable: $stale_temp" >&2
      failed=1
    fi
  done <"$stale_list_path"
else
  failed=1
fi
rm -f -- "$stale_list_path"
stale_list_path=""

# A crash before a claim rename can leave the pre-created owner marker alone.
# Remove only markers whose claim payload is absent; a marker beside a payload
# is ownership evidence and must survive for recovery.
stale_list_path="$(mktemp "${TMPDIR:-/tmp}/music-ingest-markers.XXXXXX")"
if collect_owner_markers "$inflight" "$stale_list_path"; then
  while IFS= read -r -d '' marker; do
    claim="${marker%.owner}"
    if [ -e "$claim" ]; then
      continue
    fi
    if ! rm -f -- "$marker"; then
      echo "music-ingest: cannot remove orphaned claim marker: $marker" >&2
      failed=1
      continue
    fi
    if ! sync -- "$(dirname "$marker")"; then
      echo "music-ingest: orphaned marker removal is not durable: $marker" >&2
      failed=1
    fi
  done <"$stale_list_path"
else
  failed=1
fi
rm -f -- "$stale_list_path"
stale_list_path=""

# Recover durable claims first. If an original staging path is already present,
# leave an unmarked claim and source alone and mark the run failed. An
# adapter-marked claim is owned recovery state, so it is processed first and a
# replacement source remains for the later staging scan.
list_path="$(mktemp "${TMPDIR:-/tmp}/music-ingest-inflight.XXXXXX")"
if collect_files "$inflight" "$list_path"; then
  while IFS= read -r -d '' claim; do
    rel="${claim#"$inflight"/}"
    if is_hidden_rel "$rel" || ! is_eligible "$rel"; then
      continue
    fi
    if [ -e "$staging/$rel" ] && ! claim_is_owned "$claim"; then
      echo "music-ingest: collision — staging and inflight both contain '$rel'; leaving both untouched" >&2
      failed=1
      continue
    fi
    if ! process_claim "$claim" "$rel"; then
      failed=1
    fi
  done <"$list_path"
else
  failed=1
fi
rm -f -- "$list_path"
list_path=""

# The scan sees the source paths that existed for this sweep. Once a source is
# moved, a new Syncthing version may safely reappear at the original path: this
# function only removes the claim path it owns.
list_path="$(mktemp "${TMPDIR:-/tmp}/music-ingest-staging.XXXXXX")"
if collect_files "$staging" "$list_path"; then
  while IFS= read -r -d '' src; do
    rel="${src#"$staging"/}"
    base="$(basename "$src")"
    dir="$(dirname "$src")"
    if has_syncthing_tmp "$dir" "$base"; then
      echo "music-ingest: unstable (syncthing temp sibling) — leaving: $rel" >&2
      unstable=$((unstable + 1))
      continue
    fi
    source_stat=""
    if ! source_stat="$(stat -c '%d %i %Y' -- "$src")"; then
      echo "music-ingest: source disappeared before stability check; leaving it for a later sweep: $rel" >&2
      unstable=$((unstable + 1))
      continue
    fi
    read -r source_device source_inode mtime <<<"$source_stat"
    if [ "$source_device" != "$staging_device" ]; then
      echo "music-ingest: source is on a different filesystem; retaining it: $rel" >&2
      failed=1
      continue
    fi
    age=$((now - mtime))
    if [ "$age" -lt "$stability" ]; then
      echo "music-ingest: unstable (mtime ${age}s < ${stability}s window) — leaving: $rel" >&2
      unstable=$((unstable + 1))
      continue
    fi

    claim="$inflight/$rel"
    claim_parent="$(dirname "$claim")"
    if ! claim_parent_real="$(realpath -m -- "$claim_parent")" || ! path_within_or_equal "$inflight" "$claim_parent_real"; then
      echo "music-ingest: claim parent escapes inflight root; retaining source: $rel" >&2
      failed=1
      continue
    fi
    if ! mkdir -p -- "$claim_parent"; then
      echo "music-ingest: cannot create claim parent; retaining source: $rel" >&2
      failed=1
      continue
    fi
    if ! claim_parent_real="$(realpath -m -- "$claim_parent")" || ! path_within_or_equal "$inflight" "$claim_parent_real"; then
      echo "music-ingest: claim parent changed outside inflight root; retaining source: $rel" >&2
      failed=1
      continue
    fi
    marker="$(claim_owner_marker "$claim")"
    if [ -L "$claim" ]; then
      echo "music-ingest: collision — inflight path is a symlink; leaving source untouched: $rel" >&2
      failed=1
      continue
    fi
    if [ -e "$claim" ]; then
      if claim_is_owned "$claim"; then
        if ! process_claim "$claim" "$rel"; then
          failed=1
        fi
      else
        echo "music-ingest: collision — staging and inflight both contain '$rel'; leaving both untouched" >&2
        failed=1
      fi
      continue
    fi
    if [ -e "$marker" ]; then
      echo "music-ingest: orphaned claim marker blocks source claim; leaving source recoverable: $rel" >&2
      failed=1
      continue
    fi
    # Create the owner marker before the source rename. Its fsynced existence
    # means a crash cannot leave a claimed inode indistinguishable from a
    # manually colliding inflight file.
    if ! (set -C; printf 'music-ingest-v1\n%s\n%s\n%s\n' "$source_device" "$source_inode" "$mtime" >"$marker"); then
      echo "music-ingest: cannot record claim ownership; retaining source: $rel" >&2
      failed=1
      continue
    fi
    if ! sync -- "$claim_parent"; then
      echo "music-ingest: claim marker is not durable; retaining source: $rel" >&2
      rm -f -- "$marker" || true
      failed=1
      continue
    fi
    # --no-clobber ensures a claim created concurrently cannot be replaced.
    # GNU mv returns success when -n skips an existing target, so -v supplies a
    # reliable action witness: output means this invocation performed the
    # rename; empty output means it owns neither path. This also lets a new
    # Syncthing version safely reappear at $src immediately after our rename.
    move_output=""
    if ! move_output="$(mv -nvT -- "$src" "$claim" 2>&1)"; then
      rm -f -- "$marker" || true
      if [ -e "$src" ]; then
        echo "music-ingest: could not claim source; leaving it recoverable: $rel" >&2
        failed=1
      else
        echo "music-ingest: source disappeared before claim; leaving state for a later sweep: $rel" >&2
        unstable=$((unstable + 1))
      fi
      continue
    fi
    if [ -z "$move_output" ]; then
      rm -f -- "$marker" || true
      if [ -e "$src" ] && [ -e "$claim" ]; then
        echo "music-ingest: claim collision appeared concurrently; leaving both untouched: $rel" >&2
        failed=1
      else
        echo "music-ingest: source disappeared before claim; leaving state for a later sweep: $rel" >&2
        unstable=$((unstable + 1))
      fi
      continue
    fi
    if ! sync -- "$claim_parent"; then
      echo "music-ingest: claim is not durable; retaining owned input: $rel" >&2
      failed=1
      continue
    fi
    if ! process_claim "$claim" "$rel"; then
      failed=1
    fi
  done <"$list_path"
else
  failed=1
fi

echo "music-ingest: done — ingested=$ingested deduped=$deduped conflicted=$conflicted unstable=$unstable failed=$failed"
[ "$failed" -eq 0 ] || exit 1
[ "$conflicted" -eq 0 ] || exit 3
