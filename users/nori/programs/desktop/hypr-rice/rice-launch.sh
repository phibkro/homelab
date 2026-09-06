#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  printf 'rice-launch: missing command argv\n' >&2
  exit 64
fi

case ${RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS_SET-} in
  1)
    export XDG_DATA_DIRS=${RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS-}
    ;;
  0)
    unset XDG_DATA_DIRS
    ;;
  *)
    printf 'rice-launch: missing original XDG environment marker\n' >&2
    exit 64
    ;;
esac

unset RICE_PALETTE_ACTIVE
unset RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS_SET
unset RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS
unset RICE_PRIVATE_DATA_DIR
unset RICE_LAUNCH_PREFIX_BIN
unset RICE_PALETTE_SELF
unset DESKTOP_ENTRY_ID
unset FUZZEL_DESKTOP_FILE_ID
unset DESKTOP_ENTRY_PATH
unset DESKTOP_ENTRY_ACTION
unset DESKTOP_ENTRY_NAME
unset DESKTOP_ENTRY_NAME_L
unset DESKTOP_ENTRY_COMMENT
unset DESKTOP_ENTRY_COMMENT_L
unset DESKTOP_ENTRY_ICON
unset DESKTOP_ENTRY_GENERICNAME
unset DESKTOP_ENTRY_GENERICNAME_L
unset DESKTOP_ENTRY_ACTION_NAME
unset DESKTOP_ENTRY_ACTION_NAME_L
unset DESKTOP_ENTRY_ACTION_ICON

exec "$@"
