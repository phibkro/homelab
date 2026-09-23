#!/usr/bin/env bash
# Real filesystem, Git, signal, pipe and process-lock tests; does not boot a VM.
set -euo pipefail
helper="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vm-lifecycle.sh"
scratch="$(mktemp -d)"
kept_pid=""
guardian_pid=""
cleanup() {
  [[ -z "$kept_pid" ]] || kill "$kept_pid" 2>/dev/null || true
  [[ -z "$guardian_pid" ]] || kill "$guardian_pid" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT
mkdir "$scratch/repo"
git -C "$scratch/repo" init --quiet
git -C "$scratch/repo" config user.name fixture
git -C "$scratch/repo" config user.email fixture@example.invalid
printf '.artifacts/\n' > "$scratch/repo/.gitignore"
printf 'initial\n' > "$scratch/repo/source.txt"
git -C "$scratch/repo" add .
git -C "$scratch/repo" -c core.hooksPath=/dev/null -c commit.gpgsign=false commit --quiet -m baseline
export VM_FIXTURE_REPO="$scratch/repo" VM_FIXTURE_HELPER="$helper" VM_FIXTURE_LOCK="$scratch/lock"
cat > "$scratch/run.sh" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
source "$VM_FIXTURE_HELPER"
vm_lifecycle_init "$VM_FIXTURE_REPO" "$VM_FIXTURE_LOCK"
case "$1" in
  success) vm_phase complete ;;
  mutate) printf 'changed\n' >> "$VM_FIXTURE_REPO/source.txt"; vm_phase complete ;;
  incomplete) : ;;
  interrupted) kill -TERM "$$" ;;
  logged-failure) vm_phase convergence; vm_run_logged fixture.log bash -c 'echo visible-progress; exit 23' ;;
  keep)
    sleep 60 &
    qemu_pid=$!
    vm_guard_process
    vm_phase fixture-process
    exit 9
    ;;
  cleanup)
    sleep 60 &
    qemu_pid=$!
    vm_guard_process
    vm_phase complete
    ;;
esac
RUNNER
run_case() {
  local mode="$1" expected="$2" status=0
  PI_VM_STATE_DIR="$scratch/$mode" bash "$scratch/run.sh" "$mode" > "$scratch/$mode.log" 2>&1 || status=$?
  [[ "$status" == "$expected" ]] || { cat "$scratch/$mode.log" >&2; return 1; }
}
run_case success 0
jq -e '.outcome=="passed" and .workingState.unchanged and .phase=="complete"' "$scratch/success/result.json" >/dev/null
run_case incomplete 1
jq -e '.outcome=="incomplete" and .exitCode==1' "$scratch/incomplete/result.json" >/dev/null
run_case interrupted 143
jq -e '.outcome=="interrupted" and .signal=="TERM" and .exitCode==143' "$scratch/interrupted/result.json" >/dev/null
run_case logged-failure 23
jq -e '.outcome=="failed" and .phase=="convergence" and .exitCode==23' "$scratch/logged-failure/result.json" >/dev/null
grep -q visible-progress "$scratch/logged-failure.log"
run_case mutate 1
jq -e '.workingState.unchanged==false and .outcome=="incomplete"' "$scratch/mutate/result.json" >/dev/null
run_case cleanup 0
pid="$(jq -r '.process.pid' "$scratch/cleanup/result.json")"
if kill -0 "$pid" 2>/dev/null; then echo 'Owned process leaked on success' >&2; exit 1; fi
# Reuse retains prior attempt evidence and rejects unowned or implicit state.
PI_VM_REUSE=true PI_VM_STATE_DIR="$scratch/success" bash "$scratch/run.sh" success > "$scratch/reuse.log" 2>&1 || { cat "$scratch/reuse.log" >&2; exit 1; }
[[ "$(find "$scratch/success" -name result.json | wc -l)" -eq 3 ]]
mkdir "$scratch/unowned"
printf 'operator data\n' > "$scratch/unowned/keep"
if PI_VM_REUSE=true PI_VM_STATE_DIR="$scratch/unowned" bash "$scratch/run.sh" success > /dev/null 2>&1; then exit 1; fi
if PI_VM_STATE_DIR="$scratch/unowned" bash "$scratch/run.sh" success > /dev/null 2>&1; then exit 1; fi
[[ "$(cat "$scratch/unowned/keep")" == 'operator data' ]]
if PI_VM_REUSE=true bash "$scratch/run.sh" success > /dev/null 2>&1; then exit 1; fi
# Actual orphaned sleep + guardian must retain the global lock after runner exit.
PI_VM_KEEP_ON_FAILURE=true run_case keep 9
kept_pid="$(jq -r '.process.pid' "$scratch/keep/result.json")"
guardian_pid="$(jq -r '.process.lockGuardianPid' "$scratch/keep/result.json")"
kill -0 "$kept_pid"
kill -0 "$guardian_pid"
if flock --nonblock "$VM_FIXTURE_LOCK/ports.lock" true; then echo 'Preserved process lost its lock' >&2; exit 1; fi
if PI_VM_STATE_DIR="$scratch/contender" bash "$scratch/run.sh" success > /dev/null 2>&1; then exit 1; fi
[[ ! -e "$scratch/contender" ]]
kill "$kept_pid"
# The guardian releases custody even if container init leaves an orphan zombie.
for _ in {1..40}; do
  if flock --nonblock "$VM_FIXTURE_LOCK/ports.lock" true; then break; fi
  sleep 0.1
done
flock --nonblock "$VM_FIXTURE_LOCK/ports.lock" true
kept_pid=""
guardian_pid=""
printf 'Pi VM lifecycle: ownership, reuse, hashes, streamed failures, signals, cleanup, and retained process lock passed (no VM booted).\n'
