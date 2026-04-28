#!/usr/bin/env bash
# Bulk import a directory tree into Immich, creating one album per
# top-level subfolder. Hash dedup skips files already in Immich,
# making reruns idempotent and overlap with phone-app uploads safe.
#
# Usage:
#   scripts/immich-bulk-import.sh <root-path> [more-roots...]
#
# Each <root> is treated as a parent: every immediate subfolder
# becomes its own album (named after the folder). Files at the root
# itself land in an album named after the root folder.
#
# Optional env vars:
#   IMMICH_INSTANCE_URL     default http://localhost:2283/api
#   IMMICH_API_KEY          REQUIRED — generate at /user-settings → API Keys,
#                           or via the curl-login flow if the UI hides it
#   IMMICH_CONCURRENCY      default 4
#   IMMICH_IGNORE           default '._*' (macOS resource-fork files)
#   IMMICH_DELETE_DUPS      "true" to also delete local files that hashed
#                           to existing Immich assets (cleanup pass after
#                           you've verified the import looks right)
#
# Examples:
#   # Import each subfolder of /mnt/media/photos as its own album
#   scripts/immich-bulk-import.sh /mnt/media/photos
#
#   # Import multiple roots; each subfolder under each root → album
#   scripts/immich-bulk-import.sh /mnt/media/photos "/mnt/windows-ro/Users/X/Pictures/Saved Pictures"
#
#   # Cleanup pass — delete local copies that are already in Immich
#   IMMICH_DELETE_DUPS=true scripts/immich-bulk-import.sh /mnt/media/photos
#
# Caveats:
#   - Each invocation downloads + runs immich-cli via `nix shell`.
#     First call may take ~30s to fetch.
#   - Album names come from the immediate folder name. Plan your
#     directory structure to give meaningful album names.
#   - Hash dedup happens client-side; reruns are safe but re-hash
#     all files. Add --skip-hash if you trust the dedup.

set -uo pipefail

# ── config ────────────────────────────────────────────────────────
: "${IMMICH_INSTANCE_URL:=http://localhost:2283/api}"
: "${IMMICH_CONCURRENCY:=4}"
: "${IMMICH_IGNORE:=._*}"
: "${IMMICH_DELETE_DUPS:=false}"

# ── usage check ───────────────────────────────────────────────────
if [ $# -eq 0 ]; then
  sed -n '2,/^set/p' "$0" | sed 's/^# \?//; /^set/d'
  exit 1
fi

if [ -z "${IMMICH_API_KEY:-}" ]; then
  echo "ERROR: IMMICH_API_KEY not set."
  echo "Generate one at $IMMICH_INSTANCE_URL/../../../user-settings → API Keys"
  echo "Or use the curl-login flow:"
  echo "  read -sp 'pwd: ' P; echo"
  echo "  curl -s -X POST '$IMMICH_INSTANCE_URL/auth/login' -H 'Content-Type: application/json' \\"
  echo "    -d \"{\\\"email\\\":\\\"<you>\\\",\\\"password\\\":\\\"\$P\\\"}\" | grep -oP '\"accessToken\":\"[^\"]+' | cut -d'\"' -f4"
  echo "  # use accessToken to POST $IMMICH_INSTANCE_URL/api-keys"
  exit 1
fi

export IMMICH_INSTANCE_URL IMMICH_API_KEY

# ── helpers ───────────────────────────────────────────────────────
log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

immich_upload() {
  # Build the flag set; --delete-duplicates is opt-in (cleanup pass).
  local flags=(--recursive --album --concurrency "$IMMICH_CONCURRENCY" --ignore "$IMMICH_IGNORE")
  if [ "$IMMICH_DELETE_DUPS" = "true" ]; then
    flags+=(--delete-duplicates)
    warn "DELETE-DUPLICATES MODE: local files matching Immich assets will be removed."
  fi
  nix shell nixpkgs#immich-cli --command immich upload "${flags[@]}" "$@"
}

# ── main loop ─────────────────────────────────────────────────────
log "Immich CLI bulk import — instance=$IMMICH_INSTANCE_URL"

for root in "$@"; do
  if [ ! -d "$root" ]; then
    warn "Skipping (not a directory): $root"
    continue
  fi

  # Subfolders → individual albums (named after each subfolder)
  shopt -s nullglob
  subdirs=("$root"/*/)
  shopt -u nullglob

  if [ "${#subdirs[@]}" -eq 0 ]; then
    log "Root has no subfolders; importing files at root level → album '$(basename "$root")'"
    immich_upload "$root"
  else
    for sub in "${subdirs[@]}"; do
      album=$(basename "$sub")
      log "[$root] importing → album '$album'"
      immich_upload "$sub"
    done
  fi
done

log "Done."
