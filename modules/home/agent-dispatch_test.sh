#!/usr/bin/env bash
set -euo pipefail

script=${1:?usage: agent-dispatch_test.sh <agent-dispatch-source>}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/runtime" "$tmp/work"
cd "$tmp/work"

for provider in claude codex; do
  cat >"$tmp/bin/$provider" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == hold ]]; then
  sleep 5
else
  printf '%s:%s:%s:%s\n' "$AGENT_DISPATCH_PROVIDER" "$AGENT_DISPATCH_DEPTH" "$AGENT_SANDBOX_PROFILE" "$*"
fi
EOF
  sed -i "1c#!$BASH" "$tmp/bin/$provider"
  chmod +x "$tmp/bin/$provider"
done

# Unit-test the policy assembly without requiring nested namespaces inside a
# Nix build sandbox. Runtime validation separately exercises real pagu-box.
cat >"$tmp/bin/pagu-box" <<'EOF'
#!/usr/bin/env bash
: >"$PAGU_CAPTURE"
while (($#)); do
  if [[ "$1" == -- ]]; then shift; break; fi
  printf '%s\n' "$1" >>"$PAGU_CAPTURE"
  shift
done
exec "$@"
EOF
sed -i "1c#!$BASH" "$tmp/bin/pagu-box"
chmod +x "$tmp/bin/pagu-box"

export PATH="$tmp/bin:$PATH"
export XDG_RUNTIME_DIR="$tmp/runtime"
export PAGU_CAPTURE="$tmp/pagu.args"

[[ "$(bash "$script" codex -- exec task)" == "codex:1:strict:exec task" ]]
grep -Fx -- '--profile=strict' "$PAGU_CAPTURE"
grep -Fx -- '--codex' "$PAGU_CAPTURE"

[[ "$(AGENT_DISPATCH_DEPTH=1 bash "$script" claude review)" == "claude:2:strict:review" ]]
grep -Fx -- '--claude' "$PAGU_CAPTURE"

AGENT_SANDBOX_PWD_MODE=ro bash "$script" codex inspect >/dev/null
grep -Fx -- '--pwd-ro' "$PAGU_CAPTURE"

set +e
AGENT_DISPATCH_DEPTH=2 bash "$script" codex forbidden >"$tmp/depth.out" 2>&1
depth_rc=$?
AGENT_SANDBOX_PROFILE=paranoid bash "$script" claude forbidden >"$tmp/profile.out" 2>&1
profile_rc=$?
set -e
[[ $depth_rc -eq 75 ]]
[[ $profile_rc -eq 77 ]]
grep -F 'maximum delegation depth (2) reached' "$tmp/depth.out"
grep -F 'refusing to widen paranoid parent network access' "$tmp/profile.out"

# Occupy both slots with fake workers, then prove a third dispatch fails.
bash "$script" codex hold & first=$!
bash "$script" codex hold & second=$!
sleep 0.2
set +e
bash "$script" claude third >"$tmp/slots.out" 2>&1
slots_rc=$?
set -e
kill "$first" "$second" 2>/dev/null || true
wait "$first" "$second" 2>/dev/null || true
[[ $slots_rc -eq 75 ]]
grep -F 'both delegated-worker slots are occupied' "$tmp/slots.out"

echo 'agent-dispatch tests: PASS'
