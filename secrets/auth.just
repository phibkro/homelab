#!/usr/bin/env just --justfile
# Operator-facing recipes for the secrets / auth concern. Imported via
# the root Justfile.
#
# Recipes here SHELL OUT to existing scripts (`scripts/<X>.sh`) so the
# implementation stays inspectable + version-controlled outside the
# Justfile. The recipe is a one-line dispatch + invocation contract.

# Output is sensitive — copy both YAML lines, paste into
# `sops secrets/secrets.yaml`, then `just rebuild`.
# Usage: just generate-oidc-key <name>
#
# Generate raw + PBKDF2 hash for a new lan-route OIDC client; print two paste-ready sops YAML lines.
@generate-oidc-key name:
    nix shell nixpkgs#openssl nixpkgs#authelia --command bash scripts/generate-oidc-key.sh {{name}}
