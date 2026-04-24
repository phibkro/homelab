#!/usr/bin/env bash
# nori-station pre-migration inventory.
#
# Read-only capture of system state before NixOS migration.
# Writes a timestamped subdirectory into the given output directory.
# Never dumps secret file contents — only paths, sizes, ownership.
#
# Usage:
#   sudo scripts/inventory.sh <output-dir>
#
# Example (One Touch mounted at /mnt/one-touch):
#   sudo scripts/inventory.sh /mnt/one-touch/nori-migration

set -o pipefail

SCRIPT_VERSION="1"
EXPECTED_HOSTNAME="nori-station"

die() { echo "error: $*" >&2; exit 1; }
note() { echo "[inventory] $*"; }

# --- args / preflight ----------------------------------------------------

if [[ $# -ne 1 ]]; then
  echo "usage: sudo $0 <output-dir>" >&2
  exit 2
fi

OUT_ROOT="$1"

[[ $EUID -eq 0 ]] || die "must run as root (sudo). Many sources require root to read."

[[ -d "$OUT_ROOT" ]] || die "output dir does not exist: $OUT_ROOT"
[[ -w "$OUT_ROOT" ]] || die "output dir not writable: $OUT_ROOT"

# Sanity check: are we on the machine we think we are?
HOST="$(hostname)"
if [[ "$HOST" != "$EXPECTED_HOSTNAME" ]]; then
  echo "warning: hostname is '$HOST', expected '$EXPECTED_HOSTNAME'" >&2
  read -r -p "continue anyway? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || exit 1
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$OUT_ROOT/inventory-$HOST-$TS"
mkdir -p "$OUT" || die "could not create $OUT"
ERR="$OUT/99-errors.log"
: > "$ERR"

note "writing to $OUT"

# Run a command, capture stdout to a file, stderr appended to errors log.
# Tags errors with section name so the errors log stays navigable.
cap() {
  local section="$1"; shift
  local outfile="$1"; shift
  { "$@" >"$outfile"; } 2> >(sed "s|^|[$section] |" >>"$ERR")
}

# --- 00 summary ----------------------------------------------------------

{
  echo "nori inventory"
  echo "version: $SCRIPT_VERSION"
  echo "timestamp: $TS"
  echo "hostname: $HOST"
  echo "kernel: $(uname -a)"
  echo "uptime: $(uptime -p)"
  echo "runner: $(id)"
  if [[ -r /etc/os-release ]]; then
    echo "--- /etc/os-release ---"
    cat /etc/os-release
  fi
} > "$OUT/00-summary.txt" 2>>"$ERR"

# --- 01 system -----------------------------------------------------------

{
  echo "=== /proc/cpuinfo (summary) ==="
  grep -m1 'model name' /proc/cpuinfo
  echo "cores: $(nproc)"
  echo
  echo "=== /proc/meminfo ==="
  head -5 /proc/meminfo
  echo
  echo "=== kernel modules (loaded) ==="
  lsmod | awk '{print $1}' | sort
  echo
  echo "=== boot cmdline ==="
  cat /proc/cmdline
  echo
  echo "=== timezone ==="
  timedatectl 2>/dev/null || true
  echo
  echo "=== locale ==="
  locale
} > "$OUT/01-system.txt" 2>>"$ERR"

# --- 02 storage ----------------------------------------------------------

{
  echo "=== lsblk (with model) ==="
  lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT,MODEL,SERIAL,TYPE
  echo
  echo "=== blkid ==="
  blkid 2>/dev/null || true
  echo
  echo "=== mount ==="
  mount
  echo
  echo "=== df -h ==="
  df -h
  echo
  echo "=== df -i (inodes) ==="
  df -i
  echo
  echo "=== /etc/fstab ==="
  cat /etc/fstab 2>/dev/null || true
  echo
  echo "=== /proc/swaps ==="
  cat /proc/swaps
  echo
  echo "=== smart (if smartctl present) ==="
  if command -v smartctl >/dev/null 2>&1; then
    for dev in /dev/nvme0n1 /dev/nvme1n1 /dev/sda /dev/sdb; do
      [[ -b $dev ]] || continue
      echo "--- $dev ---"
      smartctl -i "$dev" 2>&1 || true
      echo
    done
  else
    echo "smartctl not installed"
  fi
} > "$OUT/02-storage.txt" 2>>"$ERR"

# --- 03 network ----------------------------------------------------------

{
  echo "=== ip addr ==="
  ip -br addr
  echo
  ip addr
  echo
  echo "=== ip route ==="
  ip route
  echo
  echo "=== resolv.conf ==="
  cat /etc/resolv.conf 2>/dev/null || true
  echo
  echo "=== /etc/hosts ==="
  cat /etc/hosts
  echo
  echo "=== /etc/hostname ==="
  cat /etc/hostname
  echo
  echo "=== listening sockets (ss -tulnp) ==="
  ss -tulnp
  echo
  echo "=== iptables (legacy) ==="
  iptables -L -n -v 2>&1 || true
  echo
  echo "=== nftables ==="
  nft list ruleset 2>&1 || true
  echo
  echo "=== ufw ==="
  ufw status verbose 2>&1 || true
  echo
  echo "=== tailscale status (if present) ==="
  if command -v tailscale >/dev/null 2>&1; then
    tailscale status 2>&1 || true
    echo "--- tailscale ip ---"
    tailscale ip 2>&1 || true
  else
    echo "tailscale not installed"
  fi
} > "$OUT/03-network.txt" 2>>"$ERR"

# --- 04 services ---------------------------------------------------------

{
  echo "=== systemctl list-units --type=service --state=running ==="
  systemctl list-units --type=service --state=running --no-pager --no-legend
  echo
  echo "=== systemctl list-unit-files --state=enabled ==="
  systemctl list-unit-files --state=enabled --no-pager --no-legend
  echo
  echo "=== systemctl list-timers ==="
  systemctl list-timers --no-pager --no-legend
  echo
  echo "=== failed units ==="
  systemctl --failed --no-pager --no-legend
} > "$OUT/04-services.txt" 2>>"$ERR"

# Capture unit definitions for services we know we care about.
# `systemctl cat` reveals ExecStart, WorkingDirectory, EnvironmentFile — useful
# for reconstructing the service in NixOS without digging through /etc.
mkdir -p "$OUT/04-units"
for svc in ollama open-webui jellyfin cloudflared tailscaled smbd nmbd \
           filebrowser docker containerd ssh sshd systemd-networkd \
           systemd-resolved NetworkManager; do
  out_file="$OUT/04-units/${svc}.unit.txt"
  if systemctl cat "$svc" >"$out_file" 2>/dev/null; then
    :
  else
    rm -f "$out_file"
  fi
done

# --- 05 docker -----------------------------------------------------------

if command -v docker >/dev/null 2>&1; then
  mkdir -p "$OUT/05-docker-inspect"
  {
    echo "=== docker version ==="
    docker version 2>&1 || true
    echo
    echo "=== docker info ==="
    docker info 2>&1 || true
    echo
    echo "=== docker ps -a ==="
    docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>&1 || true
    echo
    echo "=== docker volume ls ==="
    docker volume ls 2>&1 || true
    echo
    echo "=== docker network ls ==="
    docker network ls 2>&1 || true
    echo
    echo "=== docker image ls ==="
    docker image ls 2>&1 || true
  } > "$OUT/05-docker.txt" 2>>"$ERR"

  # Full inspect JSON per container (contains env vars, volumes, networks,
  # restart policy — everything compose2nix needs).
  # WARNING: may contain secrets in env vars. Output directory is on a
  # removable drive you control; review before sharing.
  while read -r cid cname; do
    [[ -z $cid ]] && continue
    safe="${cname//\//_}"
    docker inspect "$cid" > "$OUT/05-docker-inspect/${safe}.json" \
      2>>"$ERR" || true
  done < <(docker ps -a --format '{{.ID}} {{.Names}}' 2>/dev/null)

  # docker-compose files anywhere on system
  {
    echo "=== compose files found ==="
    find /etc /home /root /srv /opt -maxdepth 6 \
      \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' \
         -o -name 'compose.yml' -o -name 'compose.yaml' \) \
      -printf '%p\t%s bytes\t%TY-%Tm-%Td\n' 2>/dev/null || true
  } > "$OUT/05-docker-compose-files.txt" 2>>"$ERR"
else
  echo "docker not installed" > "$OUT/05-docker.txt"
fi

# --- 06 packages ---------------------------------------------------------

{
  echo "=== dpkg -l (installed) ==="
  dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' 2>/dev/null \
    | grep -v 'deinstall ok' || true
  echo
  echo "=== apt-mark showmanual (manually installed) ==="
  apt-mark showmanual 2>/dev/null || true
  echo
  echo "=== snap list ==="
  snap list 2>&1 || true
  echo
  echo "=== flatpak list ==="
  flatpak list 2>&1 || true
  echo
  echo "=== binaries in /usr/local ==="
  ls -la /usr/local/bin /usr/local/sbin 2>/dev/null || true
  echo
  echo "=== /opt contents ==="
  ls -la /opt 2>/dev/null || true
} > "$OUT/06-packages.txt" 2>>"$ERR"

# --- 07 users ------------------------------------------------------------

{
  echo "=== human users (uid >= 1000, < nobody) ==="
  getent passwd | awk -F: '$3 >= 1000 && $3 < 65534'
  echo
  echo "=== groups with members ==="
  getent group | awk -F: '$4 != ""'
  echo
  echo "=== sudoers files (ownership/perms only) ==="
  ls -la /etc/sudoers /etc/sudoers.d/ 2>/dev/null || true
  echo
  echo "=== authorized_keys (paths + sizes only — not contents) ==="
  find /home /root -maxdepth 4 -name authorized_keys \
    -printf '%p\t%s bytes\tmode=%m\tuid=%U\n' 2>/dev/null || true
  echo
  echo "=== /etc/ssh/sshd_config (redacted) ==="
  # Strip comments/blank lines so we see only effective config.
  grep -vE '^\s*(#|$)' /etc/ssh/sshd_config 2>/dev/null || true
} > "$OUT/07-users.txt" 2>>"$ERR"

# --- 08 configs (paths + metadata only, NOT contents) --------------------

{
  echo "=== /etc top-level listing ==="
  ls -la /etc | head -200
  echo
  echo "=== dpkg-modified files in /etc ==="
  # Non-empty files under /etc whose content differs from their package's
  # shipped version — these are the configs an admin actually customized.
  if command -v dpkg-query >/dev/null 2>&1; then
    dpkg-query -W -f='${Conffiles}\n' '*' 2>/dev/null \
      | awk 'NF==3 && $3 != "obsolete"' \
      | while read -r path hash _; do
          [[ -f "$path" ]] || continue
          cur="$(md5sum "$path" 2>/dev/null | awk '{print $1}')"
          if [[ "$cur" != "$hash" ]]; then
            echo "modified: $path"
          fi
        done
  fi
  echo
  echo "=== /var/lib size summary ==="
  du -sh /var/lib/* 2>/dev/null | sort -h || true
  echo
  echo "=== docker volume directory sizes ==="
  du -sh /var/lib/docker/volumes/* 2>/dev/null | sort -h || true
  echo
  echo "=== ollama model directory (search) ==="
  find / -maxdepth 6 -type d -name 'models' -path '*/ollama/*' \
    -printf '%p\n' 2>/dev/null || true
  find / -maxdepth 6 -type d -name '.ollama' \
    -printf '%p\n' 2>/dev/null || true
  echo
  echo "=== cloudflared config paths (NOT contents) ==="
  ls -la /etc/cloudflared 2>/dev/null || true
  find /root /home -maxdepth 5 -type d -name '.cloudflared' \
    -printf '%p\n' 2>/dev/null || true
  echo
  echo "=== samba config ==="
  if command -v testparm >/dev/null 2>&1; then
    testparm -s 2>/dev/null || true
  fi
  echo
  echo "=== filebrowser config paths ==="
  find /etc /var /home /root /opt -maxdepth 5 \
    \( -name 'filebrowser.db' -o -name 'filebrowser.json' \
       -o -name '.filebrowser.yaml' \) \
    -printf '%p\t%s bytes\n' 2>/dev/null || true
  echo
  echo "=== jellyfin paths ==="
  ls -la /var/lib/jellyfin /etc/jellyfin 2>/dev/null || true
  echo
  echo "=== /root contents (names + sizes, NOT file bodies) ==="
  find /root -maxdepth 3 -printf '%p\t%s bytes\tmode=%m\n' 2>/dev/null || true
  echo
  echo "=== /home/*/dotfile inventory ==="
  for d in /home/*; do
    [[ -d "$d" ]] || continue
    echo "--- $d ---"
    find "$d" -maxdepth 2 -name '.*' \
      -printf '%p\t%s bytes\tmode=%m\n' 2>/dev/null | head -200 || true
  done
} > "$OUT/08-configs.txt" 2>>"$ERR"

# --- 09 cron / timers ----------------------------------------------------

{
  echo "=== /etc/crontab ==="
  cat /etc/crontab 2>/dev/null || true
  echo
  echo "=== /etc/cron.d ==="
  ls -la /etc/cron.d/ 2>/dev/null || true
  for f in /etc/cron.d/*; do [[ -f $f ]] && { echo "--- $f ---"; cat "$f"; }; done
  echo
  echo "=== per-user crontabs ==="
  for u in $(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}'; echo root); do
    out="$(crontab -u "$u" -l 2>/dev/null)"
    if [[ -n "$out" ]]; then
      echo "--- user: $u ---"
      echo "$out"
    fi
  done
  echo
  echo "=== systemd timers ==="
  systemctl list-timers --all --no-pager --no-legend
} > "$OUT/09-cron.txt" 2>>"$ERR"

# --- 10 gpu --------------------------------------------------------------

{
  echo "=== lspci (VGA / 3D) ==="
  lspci -nnk | grep -EA3 'VGA|3D|Display' 2>/dev/null || true
  echo
  echo "=== nvidia-smi ==="
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi 2>&1 || true
    echo
    nvidia-smi -L 2>&1 || true
  else
    echo "nvidia-smi not installed"
  fi
  echo
  echo "=== installed nvidia packages ==="
  dpkg -l | grep -iE 'nvidia|cuda' 2>/dev/null || true
} > "$OUT/10-gpu.txt" 2>>"$ERR"

# --- 11 boot / loader ----------------------------------------------------

{
  echo "=== efibootmgr -v ==="
  efibootmgr -v 2>&1 || true
  echo
  echo "=== /boot contents ==="
  ls -la /boot 2>/dev/null || true
  ls -la /boot/efi 2>/dev/null || true
  echo
  echo "=== grub config (if present) ==="
  [[ -f /etc/default/grub ]] && cat /etc/default/grub
  ls -la /boot/grub 2>/dev/null || true
} > "$OUT/11-boot.txt" 2>>"$ERR"

# --- 12 top processes (single snapshot) ---------------------------------

{
  echo "=== ps aux (sorted by rss) ==="
  ps aux --sort=-rss | head -30
  echo
  echo "=== top-level process tree ==="
  ps -efH
} > "$OUT/12-processes.txt" 2>>"$ERR"

# --- done ----------------------------------------------------------------

# Tarball the whole thing for easy transfer. Use relative paths so the
# archive extracts cleanly regardless of where it's dropped.
(
  cd "$OUT_ROOT"
  tar -cz --file="inventory-$HOST-$TS.tar.gz" "inventory-$HOST-$TS" \
    2>>"$ERR" || true
)

note "done. output: $OUT"
note "archive: $OUT_ROOT/inventory-$HOST-$TS.tar.gz"
if [[ -s "$ERR" ]]; then
  note "some commands produced errors — review $ERR"
fi
