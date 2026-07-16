# ADR-0006: Track unstable on Linux and freeze Intel Mac on 26.05

- Status: Accepted
- Date: 2026-07-16

## Context

The Linux hosts need current kernels, hardware support, desktop packages, and agent tooling. Maintaining release-channel package forks for fast-moving software such as Ollama and Claude Code adds inputs and one-off overrides while still leaving the rest of each host behind.

The MacBook is different: it is an Intel `x86_64-darwin` standalone Home Manager target. Nixpkgs 26.05 is the final release supporting that platform, so following Linux onto unstable would make the Mac configuration unevaluable when support disappears.

A single `nixpkgs` and Home Manager pair cannot express both lifecycles honestly.

## Decision

The primary `nixpkgs` input tracks `nixos-unstable`; all NixOS hosts and their embedded Home Manager configurations follow it. The primary Home Manager input tracks its rolling branch and follows primary nixpkgs.

The MacBook uses separate `nixpkgs-stable` and `home-manager-darwin` inputs pinned to the matching 26.05 release branches. `flake-parts/home.nix` passes those inputs explicitly to the standalone Mac factory.

Package-specific release inputs are removed once unstable carries the required package. Ollama therefore returns to `pkgs.ollama-cuda`. A broken unstable leaf may temporarily consume a package from `nixpkgs-stable` with an adjacent removal condition; HandBrake's currently non-applying ffmpeg patch is the first such exception.

## Consequences

- Linux receives current package/module changes on each deliberate lock update.
- The lock update and full host evaluations become the migration boundary; unstable changes must pass `nix flake check` and target closure builds before activation.
- Intel Mac remains reproducible but intentionally stops receiving channel feature updates.
- Cross-platform third-party package flakes may still provide their own Darwin builds; that does not move the Mac system package set off 26.05.
- Migrating the Mac beyond 26.05 requires replacing the machine or moving its package-management strategy, then superseding this ADR.

## Alternatives considered

- **Keep every host on 26.05.** Rejected: optimizes for the retired Intel platform at the cost of every active Linux host and perpetuates package forks.
- **Move every host to unstable.** Rejected: unstable will drop `x86_64-darwin`; the Mac would lose an evaluable source.
- **Use nixpkgs master globally.** Rejected: master has less channel-level integration testing than `nixos-unstable`; it remains a narrow package escape hatch.
