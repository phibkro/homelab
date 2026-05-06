{ pkgs, lib }:
# Node.js runtime + npm. Pinned to current LTS via nodejs_22; bump
# deliberately. npm ships bundled with the nodejs derivation, so a
# project on plain npm doesn't need a separate `npm` fragment.
#
# `bash` is bundled because npm/npx postinstall scripts (notably
# @swc/core, sharp, and any package with native-module detection)
# spawn `sh` for platform probes. Outside an interactive shell —
# typically a NixOS systemd unit copying these buildInputs into
# the unit's path — `/bin/sh` isn't on PATH, and the build dies
# with `npm error enoent spawn sh ENOENT`. Dev shells already have
# bash; the cost in /nix/store is zero (bash is closure-shared).
{
  buildInputs = with pkgs; [
    nodejs_22
    bash
  ];

  claude.permissions.allow = [
    "Bash(node *)"
    "Bash(npm *)"
    "Bash(npx *)"
  ];

  shellHook = ''echo "[dev/nodejs] node $(node --version)"'';
}
