#!/usr/bin/env just --justfile
# Operator-facing recipes for the networking concern (`nori.lanRoutes`).
# Imported via the root Justfile.
#
# Health checks live in `tests/tests.just § test-routes` (Caddy +
# DNS + HTTPS reachability per declared route) and § test-authelia
# (OIDC clients ↔ declared routes).

# Useful before adding a new service — confirms what's taken so the
# eval-time port-uniqueness assertion in `modules/infra/networking/default.nix`
# doesn't bite, and avoids the cascade-rebind dance when an upstream
# module's default happens to collide. Eval-only; safe from any tree.
# Defaults to workstation (where lanRoutes are declared; Pi's lanRoutes
# are gated on Caddy presence and so always empty).
#
# List ports claimed by `nori.lanRoutes` on a host, sorted by port. Eval-only.
@list-ports host="workstation":
    nix --extra-experimental-features "nix-command flakes" eval --raw \
        .#nixosConfigurations.{{host}}.config.nori.lanRoutes \
        --apply 'lr: let pairs = builtins.attrValues (builtins.mapAttrs (n: v: { name = n; port = v.port; }) lr); sorted = builtins.sort (a: b: a.port < b.port) pairs; in (builtins.concatStringsSep "\n" (map (e: "  ${toString e.port}\t${e.name}") sorted)) + "\n"'
