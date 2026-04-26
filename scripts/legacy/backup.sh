#!/usr/bin/env bash
# nori-station pre-migration state backup.
#
# Quiesces services, rsyncs service data/state to an external drive, and
# optionally restarts services. Does NOT back up bulk media (handled by the
# separate IronWolfPro reformat phase), Nextcloud data (dropped by decision),
# or cloudflared (deferred).
#
# Usage:
#   sudo scripts/backup.sh [-y] [--no-restart] <output-dir>
#
# Example:
#   sudo scripts/backup.sh /media/OneTouch

set -o pipefail

SCRIPT_VERSION="1"
EXPECTED_HOSTNAME="nori-station"

# --- style ---------------------------------------------------------------

die()  { echo "error: $*" >&2; exit 1; }
note() { echo "[backup] $*"; }
step() { echo; echo "=== $* ==="; }

# --- args ----------------------------------------------------------------

ASSUME_YES=0
RESTART=1
OUT_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y)            ASSUME_YES=1; shift ;;
    --no-restart)  RESTART=0; shift ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*)            die "unknown flag: $1" ;;
    *)             [[ -z "$OUT_ROOT" ]] || die "multiple output dirs given"
                   OUT_ROOT="$1"; shift ;;
  esac
done

[[ -n "$OUT_ROOT" ]] || { echo "usage: sudo $0 [-y] [--no-restart] <output-dir>" >&2; exit 2; }

# --- preflight -----------------------------------------------------------

[[ $EUID -eq 0 ]] || die "must run as root (sudo)"

HOST="$(hostname)"
if [[ "$HOST" != "$EXPECTED_HOSTNAME" ]]; then
  echo "warning: hostname is '$HOST', expected '$EXPECTED_HOSTNAME'" >&2
  [[ $ASSUME_YES -eq 1 ]] || { read -r -p "continue anyway? [y/N] " a; [[ "$a" =~ ^[yY]$ ]] || exit 1; }
fi

[[ -d "$OUT_ROOT" ]] || die "output dir does not exist: $OUT_ROOT"
[[ -w "$OUT_ROOT" ]] || die "output dir not writable: $OUT_ROOT"

# --- sources -------------------------------------------------------------
#
# Each source is a pair: <label>:<path>. Label becomes the subdirectory
# under the backup root. Paths that don't exist at backup time are skipped
# with a warning (rsync makes this cheap to decide per-path at run time).

SOURCES=(
  "docker-services:/home/nori/services"
  "ollama-share:/usr/share/ollama/.ollama"
  "ollama-home:/home/nori/.ollama"
  "tailscale-state:/var/lib/tailscale"
  "samba-lib:/var/lib/samba"
  "etc-samba:/etc/samba"
  "ssh-nori:/home/nori/.ssh"
  "ssh-root:/root/.ssh"
)

# --- size estimate + space check -----------------------------------------

step "size estimate"
REQUIRED_BYTES=0
for pair in "${SOURCES[@]}"; do
  label="${pair%%:*}"
  path="${pair#*:}"
  if [[ -e "$path" ]]; then
    bytes="$(du -sb --apparent-size "$path" 2>/dev/null | awk '{print $1}')"
    bytes="${bytes:-0}"
    REQUIRED_BYTES=$(( REQUIRED_BYTES + bytes ))
    printf '  %-20s %10d bytes   %s\n' "$label" "$bytes" "$path"
  else
    printf '  %-20s %s\n' "$label" "(missing — will skip)"
  fi
done

AVAILABLE_BYTES="$(df -B1 --output=avail "$OUT_ROOT" | tail -1 | tr -d ' ')"
HUMAN_REQ="$(numfmt --to=iec --suffix=B "$REQUIRED_BYTES")"
HUMAN_AVAIL="$(numfmt --to=iec --suffix=B "$AVAILABLE_BYTES")"
note "total source size: ${HUMAN_REQ}"
note "available at $OUT_ROOT: ${HUMAN_AVAIL}"

# Add 10% headroom for filesystem overhead / minor concurrent growth.
NEEDED=$(( REQUIRED_BYTES * 11 / 10 ))
if (( AVAILABLE_BYTES < NEEDED )); then
  die "insufficient space at $OUT_ROOT (need ~$(numfmt --to=iec --suffix=B "$NEEDED") incl. 10% headroom)"
fi

# --- confirm -------------------------------------------------------------

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$OUT_ROOT/nori-backup-$TS"

cat <<EOF

about to:
  1. stop docker compose projects: services, filebrowser, open-webui
  2. stop ollama, smbd, nmbd
  3. rsync ${#SOURCES[@]} sources → $OUT
  4. $( (( RESTART )) && echo "restart stopped services" || echo "leave services stopped (--no-restart)")

EOF

if (( ! ASSUME_YES )); then
  read -r -p "proceed? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { note "aborted"; exit 1; }
fi

mkdir -p "$OUT" || die "could not create $OUT"
ERR="$OUT/errors.log"
: > "$ERR"

# Record pre-stop status for forensics.
docker ps -a > "$OUT/pre-stop-docker-ps.txt" 2>>"$ERR" || true
systemctl status ollama smbd nmbd --no-pager > "$OUT/pre-stop-systemctl.txt" 2>>"$ERR" || true

# --- quiesce -------------------------------------------------------------
#
# Track what we stopped so we only restart those (don't spuriously start
# services that were already down, e.g. filebrowser's crashloop).

STOPPED_COMPOSE=()
STOPPED_UNITS=()

stop_compose() {
  local file="$1"
  if [[ -f "$file" ]]; then
    note "docker compose -f $file stop"
    if docker compose -f "$file" stop >>"$ERR" 2>&1; then
      STOPPED_COMPOSE+=("$file")
    else
      echo "warning: docker compose stop failed for $file" >&2
    fi
  else
    echo "warning: compose file missing: $file" >&2
  fi
}

stop_unit() {
  local unit="$1"
  if systemctl is-active --quiet "$unit"; then
    note "systemctl stop $unit"
    if systemctl stop "$unit" >>"$ERR" 2>&1; then
      STOPPED_UNITS+=("$unit")
    else
      echo "warning: failed to stop $unit" >&2
    fi
  fi
}

step "quiesce services"
stop_compose /home/nori/services/docker-compose.yml
stop_compose /home/nori/services/filebrowser/docker-compose.yml
stop_compose /home/nori/services/open-webui/docker-compose.yml
stop_unit ollama.service
stop_unit smbd.service
stop_unit nmbd.service

# Brief pause lets the containers flush and close file handles.
sleep 3

# --- rsync ---------------------------------------------------------------
#
# Flags:
#   -a         archive (recursive, preserve perms/times/symlinks/ownership)
#   -H         preserve hardlinks (ollama uses them for model blobs)
#   -A -X      preserve ACLs and xattrs
#   --numeric-ids   UIDs stay numeric, so NixOS restore maps correctly
#   --partial  keep partial files on interrupt
#   --info=stats2,progress2  summary + running progress

RSYNC_FLAGS=(-aHAX --numeric-ids --partial --info=stats2,progress2,flist0)
FAILED_SRCS=()
OK_SRCS=()

step "rsync"
for pair in "${SOURCES[@]}"; do
  label="${pair%%:*}"
  path="${pair#*:}"
  [[ -e "$path" ]] || { note "skip $label (missing): $path"; continue; }

  dest="$OUT/$label"
  mkdir -p "$dest"
  note "$label  <-  $path"

  # Trailing slash on src means "contents of src", mirroring src INTO dest.
  if rsync "${RSYNC_FLAGS[@]}" "$path/" "$dest/" 2>>"$ERR"; then
    OK_SRCS+=("$label")
  else
    echo "rsync failed for $label (continuing)" | tee -a "$ERR" >&2
    FAILED_SRCS+=("$label")
  fi
done

# --- manifest ------------------------------------------------------------

step "manifest"
{
  echo "nori backup manifest"
  echo "version: $SCRIPT_VERSION"
  echo "timestamp: $TS"
  echo "host: $HOST"
  echo "output: $OUT"
  echo
  echo "sources (successful):"
  for s in "${OK_SRCS[@]}"; do
    d="$OUT/$s"
    size="$(du -sb --apparent-size "$d" | awk '{print $1}')"
    count="$(find "$d" -type f 2>/dev/null | wc -l)"
    printf '  %-20s %12s bytes   %8d files   %s\n' \
      "$s" "$size" "$count" "$d"
  done
  if (( ${#FAILED_SRCS[@]} > 0 )); then
    echo
    echo "sources (failed — see errors.log):"
    for s in "${FAILED_SRCS[@]}"; do echo "  $s"; done
  fi
} > "$OUT/manifest.txt"

# Spot-check: sha256 the first 10 files from each source so future-you can
# verify non-corruption without rescanning everything.
step "sample checksums"
{
  for s in "${OK_SRCS[@]}"; do
    d="$OUT/$s"
    echo "--- $s ---"
    find "$d" -type f | head -10 | while read -r f; do
      sha256sum "$f"
    done
  done
} > "$OUT/sample-checksums.txt" 2>>"$ERR"

# --- restart (optional) --------------------------------------------------

if (( RESTART )); then
  step "restart services"
  for unit in "${STOPPED_UNITS[@]}"; do
    note "systemctl start $unit"
    systemctl start "$unit" 2>>"$ERR" || echo "warning: failed to start $unit" >&2
  done
  for file in "${STOPPED_COMPOSE[@]}"; do
    note "docker compose -f $file start"
    docker compose -f "$file" start >>"$ERR" 2>&1 \
      || echo "warning: compose start failed for $file" >&2
  done
else
  note "services left stopped (--no-restart)"
fi

# --- summary -------------------------------------------------------------

step "done"
note "backup:   $OUT"
note "manifest: $OUT/manifest.txt"
note "ok:       ${#OK_SRCS[@]}  failed: ${#FAILED_SRCS[@]}"
if [[ -s "$ERR" ]]; then
  note "errors were recorded — review $ERR"
fi
if (( ${#FAILED_SRCS[@]} > 0 )); then
  exit 3
fi
