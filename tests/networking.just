#!/usr/bin/env just --justfile
# Operator-facing recipes for the compiler-owned route projection.
# Imported via the root Justfile.
#
# Health checks live in `tests/tests.just § test-routes` (deployed Pi Caddy,
# DNS, and HTTPS reachability per active route) and § test-authelia
# (Authelia runtime health and generated OIDC clients).

# List every active route and port from the pure inventory. The compiler
# rejects duplicate ports before either NixOS or Ansible evaluation.
@list-ports:
    nix --extra-experimental-features "nix-command flakes" eval --raw \
        .#lib.noriInventory.routes \
        --apply 'routes: let pairs = builtins.attrValues (builtins.mapAttrs (name: route: { inherit name; port = route.port; }) routes); sorted = builtins.sort (a: b: a.port < b.port) pairs; in (builtins.concatStringsSep "\n" (map (route: "  ${toString route.port}\t${route.name}") sorted)) + "\n"'
