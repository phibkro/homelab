#!/usr/bin/env bash
set -euo pipefail

fuzzel_bin=${FUZZEL_BIN:-$(command -v fuzzel || true)}
private_data_dir=${RICE_PRIVATE_DATA_DIR:-}
launch_prefix_bin=${RICE_LAUNCH_PREFIX_BIN:-}
self=${RICE_PALETTE_SELF:-${BASH_SOURCE[0]}}
category_labels_text=${RICE_PALETTE_CATEGORIES:-}

for entry in \
  "fuzzel:$fuzzel_bin" \
  "private XDG data root:$private_data_dir" \
  "launch prefix:$launch_prefix_bin" \
  "command categories:$category_labels_text"; do
  name=${entry%%:*}
  value=${entry#*:}
  if [[ -z $value ]]; then
    printf 'rice-palette: %s is not configured\n' "$name" >&2
    exit 64
  fi
done

read -r -a category_labels <<<"$category_labels_text"

is_category() {
  local requested=$1 candidate
  for candidate in "${category_labels[@]}"; do
    [[ $requested != "$candidate" ]] || return 0
  done
  return 1
}

if [[ ${RICE_PALETTE_ACTIVE:-0} != 1 ]]; then
  if [[ ${XDG_DATA_DIRS+x} ]]; then
    export RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS_SET=1
    export RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS=$XDG_DATA_DIRS
    base_data_dirs=$XDG_DATA_DIRS
  else
    export RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS_SET=0
    export RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS=
    base_data_dirs=/usr/local/share:/usr/share
  fi
  export XDG_DATA_DIRS="$private_data_dir:$base_data_dirs"
  export RICE_PALETTE_ACTIVE=1
fi

application_args=(
  "--fields=filename,name,generic,keywords"
  --launch-prefix "$launch_prefix_bin"
)

mode=${1:-frequent}
case "$mode:$#" in
  frequent:0|frequent:1)
    exec "$fuzzel_bin" "${application_args[@]}"
    ;;
  alphabetical:1)
    exec "$fuzzel_bin" "${application_args[@]}" --no-sort --match-workers=0
    ;;
  categories:1)
    set +e
    category=$(
      printf '%s\n' "${category_labels[@]}" |
        "$fuzzel_bin" --dmenu --only-match --prompt 'category: '
    )
    status=$?
    set -e
    [[ $status -eq 1 ]] && exit 0
    [[ $status -eq 0 ]] || exit "$status"
    [[ -n $category ]] || exit 0
    if is_category "$category"; then
      exec "$BASH" "$self" category "$category"
    fi
    printf 'rice-palette: invalid category: %s\n' "$category" >&2
    exit 64
    ;;
  category:2)
    if is_category "$2"; then
      exec "$fuzzel_bin" "${application_args[@]}" --search "$2:"
    fi
    printf 'rice-palette: invalid category: %s\n' "$2" >&2
    exit 64
    ;;
  *)
    printf 'usage: rice-palette [frequent|alphabetical|categories|category CATEGORY]\n' >&2
    exit 64
    ;;
esac
