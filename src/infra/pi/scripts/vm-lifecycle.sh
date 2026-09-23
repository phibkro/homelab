#!/usr/bin/env bash
# Lifecycle shared by the real VM runner and its process/filesystem tests.
vm_source_hash() {
  {
    git -C "$vm_repo_root" rev-parse HEAD || return
    git -C "$vm_repo_root" diff --no-ext-diff --no-textconv --binary HEAD -- || return
    git -C "$vm_repo_root" diff --no-ext-diff --no-textconv --cached --binary -- || return
    git -C "$vm_repo_root" ls-files --others --exclude-standard -z | while IFS= read -r -d '' path; do
      printf '%s\0' "$path"
      if [[ -L "$vm_repo_root/$path" ]]; then
        readlink "$vm_repo_root/$path"
      elif [[ -f "$vm_repo_root/$path" ]]; then
        sha256sum < "$vm_repo_root/$path"
      fi
    done
  } | sha256sum | cut -d ' ' -f 1
}

vm_lifecycle_init() {
  vm_repo_root="$(realpath "${1:?repository root is required}")"
  # Only lifecycle fixtures supply the second argument. The VM runner always
  # uses the user-global path, independent of checkout and TMPDIR.
  local lock_root="${2:-/tmp/homelab-pi-vm-$UID}" lock_path
  if [[ ! -e "$lock_root" && ! -L "$lock_root" ]]; then mkdir -m 0700 "$lock_root"; fi
  if [[ -L "$lock_root" || ! -d "$lock_root" || ! -O "$lock_root" || $(stat -c %a "$lock_root") != 700 ]]; then
    echo "Refusing non-private lock directory: $lock_root" >&2; return 1
  fi
  lock_path="$lock_root/ports.lock"
  if [[ -L "$lock_path" || ( -e "$lock_path" && ( ! -f "$lock_path" || ! -O "$lock_path" ) ) ]]; then
    echo "Refusing non-owned lock: $lock_path" >&2; return 1
  fi
  exec {vm_lock_fd}>"$lock_path"
  if ! flock --exclusive --nonblock "$vm_lock_fd"; then
    echo "Another Pi VM owns the fixed ports/cache (lock $lock_path)." >&2; return 1
  fi
  if [[ ${PI_VM_REUSE:-false} == true && -z ${PI_VM_STATE_DIR:-} ]]; then
    echo 'PI_VM_REUSE=true requires an explicit PI_VM_STATE_DIR.' >&2; return 1
  fi
  if [[ -n ${PI_VM_STATE_DIR:-} ]]; then
    state_dir="$(realpath -m "$PI_VM_STATE_DIR")"
    if [[ ${PI_VM_REUSE:-false} == true ]]; then
      [[ -d "$state_dir" && ! -L "$PI_VM_STATE_DIR" && -O "$state_dir" && $(stat -c %a "$state_dir") == 700 ]] || {
        echo 'Reuse requires an owned state directory.' >&2; return 1;
      }
      [[ -f "$state_dir/owner.json" && ! -L "$state_dir/owner.json" && -O "$state_dir/owner.json" ]] || {
        echo 'Reuse requires a regular owned marker.' >&2; return 1;
      }
      jq -e --arg repo "$vm_repo_root" --argjson uid "$UID" \
        '.schema == 1 and .repo == $repo and .uid == $uid' "$state_dir/owner.json" >/dev/null || {
        echo 'Reuse requires the ownership marker for this checkout.' >&2; return 1;
      }
    else
      # mkdir is deliberately exclusive: never clear an existing directory.
      mkdir -m 0700 "$state_dir" || return 1
    fi
  else
    mkdir -p "$vm_repo_root/.artifacts/pi-vm"
    state_dir="$(mktemp -d "$vm_repo_root/.artifacts/pi-vm/run.XXXXXXXX")"
  fi
  if [[ ${PI_VM_REUSE:-false} != true ]]; then
    jq -n --arg repo "$vm_repo_root" --argjson uid "$UID" \
      '{schema:1,repo:$repo,uid:$uid}' > "$state_dir/owner.json"
  fi
  attempt_dir="$(mktemp -d "$state_dir/attempt.XXXXXXXX")"
  revision="$(git -C "$vm_repo_root" rev-parse HEAD)"
  initial_source_hash="$(vm_source_hash)"
  phase=initialized
  qemu_pid=""
  vm_guardian_pid=""
  vm_interrupted=""
  trap 'vm_finish "$?"' EXIT
  trap 'vm_interrupted=INT; exit 130' INT
  trap 'vm_interrupted=TERM; exit 143' TERM
  trap 'vm_interrupted=HUP; exit 129' HUP
  printf 'Pi VM state: %s\nAttempt evidence: %s\n' "$state_dir" "$attempt_dir"
}

vm_phase() {
  phase="$1"
  printf '[Pi VM] %s\n' "$phase"
}

vm_record_command() {
  printf '%q ' "$@" >> "$attempt_dir/commands.log"
  printf '\n' >> "$attempt_dir/commands.log"
}

vm_run_logged() {
  local log="$1"
  shift
  vm_record_command "$@"
  "$@" 2>&1 | tee "$attempt_dir/$log"
}

vm_process_alive() {
  local process_stat
  kill -0 "$qemu_pid" 2>/dev/null || return 1
  [[ -r "/proc/$qemu_pid/stat" ]] || return 1
  process_stat="$(<"/proc/$qemu_pid/stat")"
  # A terminated orphan can remain a zombie under container init; it owns no VM.
  [[ ${process_stat##*) } != Z* ]]
}

vm_guard_process() {
  # This shell inherits the flock descriptor. It retains custody if the runner
  # exits while explicitly preserving QEMU, even if QEMU closes inherited FDs.
  (
    trap - EXIT INT TERM HUP
    while vm_process_alive; do sleep 1; done
  ) &
  vm_guardian_pid=$!
}

vm_finish() {
  local status="$1" outcome=failed preserved=false final_hash log_files
  trap - EXIT INT TERM HUP ERR
  set +e
  if [[ -n "$vm_interrupted" ]]; then
    outcome=interrupted
  elif [[ "$status" == 0 && "$phase" == complete ]]; then
    outcome=passed
  elif [[ "$status" == 0 ]]; then
    outcome=incomplete
    status=1
  fi
  if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
    if [[ "$status" != 0 && -z "$vm_interrupted" && ${PI_VM_KEEP_ON_FAILURE:-false} == true ]]; then
      preserved=true
      printf 'ARM64 guest preserved: PID %s; lock guardian PID %s; SSH port 2222. Stop the guest before another run.\n' "$qemu_pid" "$vm_guardian_pid" >&2
    else
      kill "$qemu_pid" 2>/dev/null
      for _ in {1..50}; do
        kill -0 "$qemu_pid" 2>/dev/null || break
        sleep 0.2
      done
      kill -KILL "$qemu_pid" 2>/dev/null
    fi
  fi
  if [[ "$preserved" != true && -n "$qemu_pid" ]]; then
    wait "$qemu_pid" 2>/dev/null
  fi
  if [[ "$preserved" != true && -n "$vm_guardian_pid" ]]; then
    wait "$vm_guardian_pid" 2>/dev/null
  fi
  final_hash="$(vm_source_hash)" || { final_hash=unavailable; status=1; outcome=failed; }
  if [[ "$outcome" == passed && "$initial_source_hash" != "$final_hash" ]]; then
    outcome=incomplete
    status=1
    echo 'Source changed during the run; results do not validate a single source state.' >&2
  fi
  log_files="$(find "$attempt_dir" -maxdepth 1 -type f -name '*.log' -print | sort | jq -Rn '[inputs]')" || {
    log_files='[]'; status=1; outcome=failed;
  }
  jq -n --arg revision "$revision" --arg initial "$initial_source_hash" --arg final "$final_hash" \
    --arg outcome "$outcome" --arg phase "$phase" --arg signal "$vm_interrupted" \
    --arg state "$state_dir" --arg attempt "$attempt_dir" --arg repo "$vm_repo_root" \
    --arg pid "$qemu_pid" --arg guardian "$vm_guardian_pid" \
    --argjson uid "$UID" --argjson exitCode "$status" --argjson preserved "$preserved" --argjson logs "$log_files" \
    '{schema:1,revision:$revision,workingState:{initial:$initial,final:$final,unchanged:($initial==$final)},
      outcome:$outcome,exitCode:$exitCode,phase:$phase,signal:$signal,
      owner:{uid:$uid,repo:$repo},stateDirectory:$state,attemptDirectory:$attempt,
      process:{pid:$pid,lockGuardianPid:$guardian,preserved:$preserved},
      logs:$logs}' \
    > "$attempt_dir/result.json" || status=1
  cp "$attempt_dir/result.json" "$state_dir/result.json.tmp" && mv "$state_dir/result.json.tmp" "$state_dir/result.json" || status=1
  printf 'Pi VM result: %s (%s)\n' "$outcome" "$attempt_dir/result.json" >&2
  exit "$status"
}
