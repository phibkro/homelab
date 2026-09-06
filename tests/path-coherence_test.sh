#!/usr/bin/env bash
set -euo pipefail

checker="$(realpath "${1:?path-coherence checker required}")"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

mkdir -p "$scratch/docs/reference" "$scratch/lib"
printf '{}\n' > "$scratch/lib/live.nix"
cat > "$scratch/docs/reference/paths.md" <<'EOF'
The active helper is `lib/live.nix`.
The removed helper is `lib/removed.nix`.
The package helper is imported from `pkgs.path + "/nixos/lib/eval-config.nix"`.
EOF

if bash "$checker" "$scratch" > "$scratch/output" 2>&1; then
  echo "path-coherence accepted a stale lib/ reference" >&2
  exit 1
fi
grep -Fq "dead reference 'lib/removed.nix'" "$scratch/output"
if grep -Fq "dead reference 'lib/live.nix'" "$scratch/output"; then
  echo "path-coherence rejected an existing lib/ reference" >&2
  exit 1
fi

cat > "$scratch/docs/reference/paths.md" <<'EOF'
The active helper is `lib/live.nix`.
The package helper is imported from `pkgs.path + "/nixos/lib/eval-config.nix"`.
EOF
bash "$checker" "$scratch" >/dev/null
printf 'path-coherence: lib root positive and negative cases passed\n'
