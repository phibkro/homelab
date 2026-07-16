#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: agent-dispatch [--read-only] <claude|codex> [--] [arguments...]

Starts a cross-provider agent in a strict OS sandbox with bounded recursive
depth and one of two shared worker slots. Use raw claude/codex only for
operator-led sessions.
EOF
  exit 2
}

read_only=0
if [[ "${1:-}" == "--read-only" ]]; then
  read_only=1
  shift
fi

provider="${1:-}"
case "$provider" in
  claude|codex) shift ;;
  *) usage ;;
esac

if [[ "${1:-}" == "--" ]]; then
  shift
fi

depth="${AGENT_DISPATCH_DEPTH:-0}"
if [[ ! "$depth" =~ ^[0-9]+$ ]]; then
  echo "agent-dispatch: invalid AGENT_DISPATCH_DEPTH: $depth" >&2
  exit 2
fi

# depth 0 lead -> depth 1 worker -> depth 2 reviewer; depth 2 cannot recurse.
readonly max_depth=2
if (( depth >= max_depth )); then
  echo "agent-dispatch: maximum delegation depth ($max_depth) reached" >&2
  exit 75
fi

# Delegation is capability-monotone. A raw/default/loose parent descends to
# strict; a strict parent stays strict. A paranoid parent has no remote network,
# so starting a cloud agent would require widening and is rejected.
parent_profile="${AGENT_SANDBOX_PROFILE:-outside}"
case "$parent_profile" in
  outside|loose|default|strict) ;;
  paranoid)
    echo "agent-dispatch: refusing to widen paranoid parent network access" >&2
    exit 77
    ;;
  *)
    echo "agent-dispatch: unknown parent sandbox profile: $parent_profile" >&2
    exit 2
    ;;
esac

parent_pwd_mode="${AGENT_SANDBOX_PWD_MODE:-rw}"
case "$parent_pwd_mode" in
  ro) read_only=1 ;;
  rw) ;;
  *)
    echo "agent-dispatch: unknown parent PWD mode: $parent_pwd_mode" >&2
    exit 2
    ;;
esac

# Sandboxed agents may inspect the canonical homelab but never edit it. Work in
# an isolated worktree outside this prefix when delegated writes are intended.
case "$PWD" in
  /srv/share/projects/homelab|/srv/share/projects/homelab/*) read_only=1 ;;
esac

runtime_root="${XDG_RUNTIME_DIR:-/tmp}/agent-dispatch-${UID}"
install -d -m 0700 "$runtime_root"

# Two slots bound breadth independently from depth. The lock descriptor remains
# inherited by the child and is released automatically when that process exits.
for slot in 1 2; do
  lock="$runtime_root/worker-${slot}.lock"
  exec {lock_fd}>"$lock"
  if flock -n "$lock_fd"; then
    export AGENT_DISPATCH_DEPTH="$((depth + 1))"
    export AGENT_DISPATCH_PROVIDER="$provider"
    export AGENT_SANDBOX_PROFILE=strict
    if (( read_only )); then
      export AGENT_SANDBOX_PWD_MODE=ro
    else
      export AGENT_SANDBOX_PWD_MODE=rw
    fi

    sandbox=(
      --profile=strict
      --env AGENT_DISPATCH_DEPTH
      --env AGENT_DISPATCH_PROVIDER
      --env AGENT_SANDBOX_PROFILE
      --env AGENT_SANDBOX_PWD_MODE
    )
    if (( read_only )); then
      sandbox+=( --pwd-ro )
    fi
    sandbox+=( "--$provider" )

    # Preserve Herdr's control plane only when the parent is already in Herdr.
    # This grants no host path the parent did not already possess.
    if [[ "${HERDR_ENV:-}" == 1 ]]; then
      for variable in \
        HERDR_ENV HERDR_WORKSPACE_ID HERDR_TAB_ID HERDR_PANE_ID \
        HERDR_SOCKET_PATH HERDR_CLIENT_SOCKET_PATH HERDR_SESSION; do
        if [[ -n "${!variable:-}" ]]; then
          sandbox+=( --env "$variable" )
        fi
      done
      if [[ -e "$HOME/.config/herdr" ]]; then
        sandbox+=( --allow "$HOME/.config/herdr" )
      fi
    fi

    exec pagu-box "${sandbox[@]}" -- "$provider" "$@"
  fi
  eval "exec ${lock_fd}>&-"
done

echo "agent-dispatch: both delegated-worker slots are occupied" >&2
exit 75
