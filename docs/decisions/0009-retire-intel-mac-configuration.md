# ADR-0009: Retire the Intel Mac configuration

- Status: Accepted
- Date: 2026-07-26
- Supersedes: ADR-0006 (Track unstable on Linux and freeze Intel Mac on 26.05)

## Context

ADR-0006 split the flake's lifecycles: Linux hosts on `nixos-unstable`, the
Intel MacBook frozen on the 26.05 pair — the final release line supporting
`x86_64-darwin`. It named its own exit condition: "Migrating the Mac beyond
26.05 requires replacing the machine or moving its package-management
strategy, then superseding this ADR."

That condition arrived from the other direction. The main `nixpkgs` input
advanced to 26.11, which **dropped `x86_64-darwin` outright**. The standalone
Mac home stopped evaluating, and because `nix flake check` evaluates every
flake output, the repository's own quality gate went red on `main` — the gate
that enforces every other invariant here. It stayed red rather than being
fixed, because the machine had already fallen out of use.

The operator confirmed the Mac is no longer in use.

## Decision

Retire the Intel Mac configuration entirely. The flake manages NixOS hosts
only and no longer emits `homeConfigurations`.

Removed: the `macbook` inventory entry, `modules/machines/macbook/`,
`flake-parts/home.nix`, the standalone home factory at `modules/home/
default.nix`, the `standaloneHomes` projection, and the `home-manager-darwin`
/ `tilth-darwin` / `pagu-darwin` inputs with their `x86_64-darwin` branches in
`modules/home/claude-code/`.

Retained deliberately:

- **`nixpkgs-stable`** — still the source for HandBrake
  (`modules/home/profiles/creative/video.nix`), the exception ADR-0006
  anticipated. Its URL still names the 26.05 *darwin* branch, which is now
  cosmetically misleading; that branch carries every platform, so the pin is
  wrong in name only. Repointing it re-resolves HandBrake and is therefore a
  deliberate bump, not a rider on this change.
- **The inventory's `kind` discriminator** — re-adding a standalone home
  stays an inventory entry rather than a schema change. Its `home-manager`
  branch is consequently unexercised; `tests/eval/deployment.nix` says so at
  the point where the assertion used to be.

## Consequences

- `nix flake check` is a usable gate again. This is the point of the change:
  a red gate enforces nothing, and every invariant in `docs/invariants.md`
  depends on it running.
- The `x86_64-darwin` EOL clock is closed. No decision is pending on
  replacement hardware or a migration path; if a Mac returns it will be
  Apple Silicon and a fresh entry.
- Remote access to homelab services from a Mac is unaffected — that was
  always Tailscale plus a browser, never the flake. Sunshine's Moonlight
  client is likewise not flake-managed.
- Tailscale ACLs still name a `macbook` device under `tag:privileged`
  (`modules/machines/pavilion/default.nix`). ACLs live in the Tailscale admin
  UI, not this flake, so that text is left alone until the device is removed
  there.

## Alternatives considered

- **Pin `nixpkgs` back to 26.05 for everything.** Rejected for the same
  reason ADR-0006 rejected it, now stronger: it would freeze four active
  Linux hosts to preserve a machine that is not used.
- **Keep the Mac config and exclude it from `nix flake check`.** Rejected:
  an output excluded from the gate is an output nothing verifies, and the
  gate's credibility is the asset being protected.
- **Leave it red and work around it.** Rejected: this is what happened, and
  it silently disabled the repository's enforcement layer.
