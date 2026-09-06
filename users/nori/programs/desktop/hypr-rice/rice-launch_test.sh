#!/usr/bin/env bash
set -euo pipefail

script=$1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
capture=$tmp/capture
metadata_vars=(
  DESKTOP_ENTRY_ID
  FUZZEL_DESKTOP_FILE_ID
  DESKTOP_ENTRY_PATH
  DESKTOP_ENTRY_ACTION
  DESKTOP_ENTRY_NAME
  DESKTOP_ENTRY_NAME_L
  DESKTOP_ENTRY_COMMENT
  DESKTOP_ENTRY_COMMENT_L
  DESKTOP_ENTRY_ICON
  DESKTOP_ENTRY_GENERICNAME
  DESKTOP_ENTRY_GENERICNAME_L
  DESKTOP_ENTRY_ACTION_NAME
  DESKTOP_ENTRY_ACTION_NAME_L
  DESKTOP_ENTRY_ACTION_ICON
)

printf '#!%s\n' "$BASH" >"$tmp/target"
cat >>"$tmp/target" <<'EOF'
set -euo pipefail
printf 'xdg=%s\n' "${XDG_DATA_DIRS-<unset>}" >"$RICE_LAUNCH_CAPTURE"
printf 'active=%s\n' "${RICE_PALETTE_ACTIVE-<unset>}" >>"$RICE_LAUNCH_CAPTURE"
printf 'private=%s\n' "${RICE_PRIVATE_DATA_DIR-<unset>}" >>"$RICE_LAUNCH_CAPTURE"
printf 'prefix=%s\n' "${RICE_LAUNCH_PREFIX_BIN-<unset>}" >>"$RICE_LAUNCH_CAPTURE"
for variable in \
  DESKTOP_ENTRY_ID FUZZEL_DESKTOP_FILE_ID DESKTOP_ENTRY_PATH \
  DESKTOP_ENTRY_ACTION DESKTOP_ENTRY_NAME DESKTOP_ENTRY_NAME_L \
  DESKTOP_ENTRY_COMMENT DESKTOP_ENTRY_COMMENT_L DESKTOP_ENTRY_ICON \
  DESKTOP_ENTRY_GENERICNAME DESKTOP_ENTRY_GENERICNAME_L \
  DESKTOP_ENTRY_ACTION_NAME DESKTOP_ENTRY_ACTION_NAME_L \
  DESKTOP_ENTRY_ACTION_ICON; do
  printf '%s=%s\n' "$variable" "${!variable-<unset>}" >>"$RICE_LAUNCH_CAPTURE"
done
printf 'args=' >>"$RICE_LAUNCH_CAPTURE"
printf '%s|' "$@" >>"$RICE_LAUNCH_CAPTURE"
EOF
chmod +x "$tmp/target"

for variable in "${metadata_vars[@]}"; do
  export "$variable=seed"
done

RICE_LAUNCH_CAPTURE=$capture \
RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS_SET=1 \
RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS=/existing \
RICE_PALETTE_ACTIVE=1 \
RICE_PRIVATE_DATA_DIR=/private \
RICE_LAUNCH_PREFIX_BIN=/prefix \
XDG_DATA_DIRS=/private:/existing \
  bash "$script" "$tmp/target" one 'two words'
grep -Fxq 'xdg=/existing' "$capture"
grep -Fxq 'active=<unset>' "$capture"
grep -Fxq 'private=<unset>' "$capture"
grep -Fxq 'prefix=<unset>' "$capture"
for variable in "${metadata_vars[@]}"; do
  grep -Fxq "$variable=<unset>" "$capture"
done
grep -Fxq 'args=one|two words|' "$capture"

RICE_LAUNCH_CAPTURE=$capture \
RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS_SET=0 \
RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS= \
RICE_PALETTE_ACTIVE=1 \
XDG_DATA_DIRS=/private:/usr/share \
  bash "$script" "$tmp/target"
grep -Fxq 'xdg=<unset>' "$capture"

if bash "$script" "$tmp/target" 2>/dev/null; then
  echo 'rice-launch accepted missing palette environment' >&2
  exit 1
fi

if RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS_SET=0 bash "$script" 2>/dev/null; then
  echo 'rice-launch accepted missing command argv' >&2
  exit 1
fi

echo 'rice-launch behavior tests passed'
