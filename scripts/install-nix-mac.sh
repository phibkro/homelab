#!/usr/bin/env bash
# Nix installer for Intel Mac (x86_64-darwin)
#
# Determinate Systems dropped x86_64-darwin support 2025-11-10. Their
# installer 404s on Intel Mac. The official upstream installer still
# supports it; this script wraps it with the polish bits Determinate
# would have given:
#   - Detects + cleans up orphaned Nix install state from previous
#     attempts (LaunchDaemons, /etc/nix, /nix, _nixbld users,
#     synthetic.conf entries, APFS volumes — see detect_orphans below)
#   - Enables flakes + nix-command experimental features (default-off
#     in upstream, default-on in Determinate)
#   - Verifies install before declaring success
#
# Usage:
#   scripts/install-nix-mac.sh
#
# Idempotent. Re-running on a healthy install is a no-op (detects + skips).
# After successful install, open a fresh terminal so PATH picks up nix.
#
# Compatible with Apple Silicon too — does no Intel-specific things;
# the platform detection happens inside the upstream installer.

set -euo pipefail

# ── helpers ───────────────────────────────────────────────────────
log()   { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
err()   { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
note()  { printf '    %s\n' "$*"; }

confirm() {
  local prompt="${1:-Proceed?}"
  read -rp "$prompt [y/N] " ans
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

require_macos() {
  [ "$(uname -s)" = "Darwin" ] || err "macOS only."
}

# ── detect orphaned install ───────────────────────────────────────
detect_orphans() {
  local found=()
  [ -f /Library/LaunchDaemons/org.nixos.nix-daemon.plist ] && found+=("LaunchDaemon: org.nixos.nix-daemon")
  [ -f /Library/LaunchDaemons/org.nixos.darwin-store.plist ] && found+=("LaunchDaemon: org.nixos.darwin-store")
  [ -d /etc/nix ] && found+=("/etc/nix (config dir)")
  [ -d /nix ] && [ "$(ls -A /nix 2>/dev/null | head -1)" = "" ] && found+=("/nix (empty stub)")
  [ -d /nix/store ] && found+=("/nix/store (existing nix install — DO NOT clean if you want to keep it!)")
  [ -f /etc/synthetic.conf ] && grep -q '^nix$' /etc/synthetic.conf 2>/dev/null && found+=("/etc/synthetic.conf has nix entry")
  if dscl . -read /Groups/_nixbld &>/dev/null; then
    found+=("_nixbld group exists")
  fi
  if diskutil apfs list 2>/dev/null | grep -q "Name:.*Nix Store"; then
    found+=("APFS volume named 'Nix Store'")
  fi

  if [ ${#found[@]} -eq 0 ]; then
    return 1
  fi

  warn "Found existing/orphaned Nix state:"
  for item in "${found[@]}"; do note "  - $item"; done
  return 0
}

# ── cleanup ───────────────────────────────────────────────────────
cleanup_orphans() {
  log "Stopping LaunchDaemons (idempotent)..."
  sudo launchctl bootout system/org.nixos.nix-daemon 2>/dev/null || true
  sudo launchctl bootout system/org.nixos.darwin-store 2>/dev/null || true

  log "Removing LaunchDaemon plists..."
  sudo rm -f /Library/LaunchDaemons/org.nixos.nix-daemon.plist
  sudo rm -f /Library/LaunchDaemons/org.nixos.darwin-store.plist

  log "Removing /etc/nix..."
  sudo rm -rf /etc/nix

  log "Removing /nix dir (will fail if it's an APFS volume — handled separately)..."
  sudo rm -rf /nix 2>/dev/null || warn "Couldn't remove /nix; check 'diskutil apfs list' for an APFS Nix volume."

  log "Removing _nixbld users (1..32) and group..."
  for u in $(seq 1 32); do
    sudo dscl . -delete /Users/_nixbld$u 2>/dev/null || true
  done
  sudo dscl . -delete /Groups/_nixbld 2>/dev/null || true

  if [ -f /etc/synthetic.conf ]; then
    log "Cleaning /etc/synthetic.conf nix entry..."
    sudo sed -i '' '/^nix$/d' /etc/synthetic.conf
    [ ! -s /etc/synthetic.conf ] && sudo rm /etc/synthetic.conf
  fi

  if diskutil apfs list 2>/dev/null | grep -q "Name:.*Nix Store"; then
    warn "APFS 'Nix Store' volume detected. Manual deletion required (avoiding data loss):"
    note "  diskutil apfs list  # find the volume's disk identifier (diskNsM)"
    note "  sudo diskutil apfs deleteVolume diskNsM"
    note "Skipping volume deletion automatically; do this yourself, then re-run this script."
    if ! confirm "Volume detected but I'll handle it manually — continue install anyway?"; then
      err "Aborting. Handle the APFS volume, then re-run."
    fi
  fi

  log "Cleanup complete."
}

# ── install ───────────────────────────────────────────────────────
install_nix() {
  log "Running upstream nixos.org Nix installer (multi-user, daemon mode)..."
  log "You'll be prompted for sudo password and asked to confirm by the installer."
  sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon
}

# ── enable flakes ─────────────────────────────────────────────────
enable_flakes() {
  log "Enabling flakes + nix-command experimental features..."
  if [ ! -f /etc/nix/nix.conf ]; then
    err "/etc/nix/nix.conf missing post-install — something went wrong."
  fi
  if grep -q '^experimental-features' /etc/nix/nix.conf; then
    log "experimental-features already configured; leaving alone."
    note "  $(grep '^experimental-features' /etc/nix/nix.conf)"
  else
    log "Adding 'experimental-features = nix-command flakes' to /etc/nix/nix.conf"
    echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf >/dev/null
  fi
}

# ── verify ────────────────────────────────────────────────────────
verify_install() {
  log "Verifying install (sourcing /etc/profile.d/nix.sh for this shell)..."
  if [ -f /etc/profile.d/nix.sh ]; then
    set +u
    # shellcheck source=/dev/null
    . /etc/profile.d/nix.sh
    set -u
  fi

  if ! command -v nix >/dev/null 2>&1; then
    warn "nix not found on PATH in this shell. Open a NEW terminal and run:"
    note "  nix --version"
    note "  nix flake metadata nixpkgs"
    return 1
  fi

  log "Nix version: $(nix --version)"
  log "Verifying flakes..."
  if nix flake metadata nixpkgs >/dev/null 2>&1; then
    log "✓ flakes working"
  else
    warn "flake metadata fetch failed — check nix-daemon status + /etc/nix/nix.conf"
  fi
}

# ── next steps ────────────────────────────────────────────────────
print_next_steps() {
  cat <<'EOF'

================================================================
  Nix install complete.

  Open a fresh terminal (current one doesn't have nix on PATH),
  then activate home-manager (assumes ~/.config/home-manager/ has
  flake.nix + home.nix):

    cd ~/.config/home-manager
    nix run home-manager/master -- switch --flake .#$(whoami)

  After verified working, prune brew duplicates incrementally:

    brew uninstall --formula <pkg>

================================================================

EOF
}

# ── main ──────────────────────────────────────────────────────────
main() {
  require_macos

  log "Mac Nix install (Intel x86_64-darwin or Apple Silicon)"
  echo

  if detect_orphans; then
    echo
    if confirm "Remove orphaned/existing state before installing?"; then
      cleanup_orphans
    else
      err "Cleanup declined; cannot proceed."
    fi
    echo
  else
    log "No orphaned state detected. Continuing with fresh install."
    echo
  fi

  install_nix
  echo
  enable_flakes
  echo
  verify_install || true
  print_next_steps
}

main "$@"
