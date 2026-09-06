#!/usr/bin/env just --justfile
# Operator-facing recipes for the services layer (per-service workloads).
# Imported via the root Justfile.

# Each personal-app manifest declares its artifact consumer unit. This recipe
# resolves that unit through the host's public inventory, so naming and
# deployability are not inferred from a filesystem convention.
# Logs stream live, exit code matches the unit's.
# Usage: just deploy-app filmder
#
# Build + publish a personal app through its inventory-declared artifact consumer.
deploy-app name:
    #!/usr/bin/env bash
    set -euo pipefail
    unit="$(nix eval --raw ".#nixosConfigurations.$(hostname).config.nori.inventory.workloads.{{name}}.artifact.consumer.unit")"
    sudo systemctl start --wait "$unit.service"
    echo ""
    echo "[deploy-app {{name}}] Last 20 log lines:"
    journalctl -u "$unit.service" --no-pager -n 20
