#!/usr/bin/env just --justfile
# Operator-facing recipes for the services layer (per-service workloads).
# Imported via the root Justfile.

# Each app's `modules/services/<name>.nix` declares a `<name>-build.service`
# oneshot — this recipe just kicks it. Operator triggers explicitly so
# `nixos-rebuild switch` stays fast (no npm-install on every rebuild).
# Logs stream live, exit code matches the unit's.
# Usage: just deploy-app filmder
#
# Build + publish a personal app's static artifact via its `<name>-build.service` oneshot.
deploy-app name:
    sudo systemctl start --wait {{name}}-build.service
    @echo ""
    @echo "[deploy-app {{name}}] Last 20 log lines:"
    @journalctl -u {{name}}-build.service --no-pager -n 20
