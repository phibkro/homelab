---
summary: Orientation for an agent working across the projects on this machine —
  the topology, how to run/build each repo, per-project cheat-sheet, conventions,
  and gotchas. Canonical here in homelab; symlinked at /srv/share/projects/AGENTS.md.
tags: [orchestration, machine, onboarding, cross-project]
---

# Working across the projects on this machine

Orientation for a fresh agent (or human) managing the multiple repos under
`/srv/share/projects` on `workstation`. Read this, then each repo's own
entrypoint (`CLAUDE.md` / `AGENTS.md`) for its specifics — this file is the map,
not the territory. Don't duplicate per-repo detail here; point to it.

## The machine (self-describing)

- **`workstation` (NixOS) is configured by the homelab flake at
  `/srv/share/projects/homelab`** — the canonical source for the whole machine
  (NixOS + home-manager). `~/.claude/` is a *generated derivation*: edit
  `homelab/home/claude-code/` + rebuild (`just rebuild`, or
  `nh os switch -H workstation`; sudo is passwordless), never `~/.claude/`
  directly. Doc-only homelab changes don't need a rebuild; config changes do.
- **Projects** live under `/srv/share/projects/` (user-agnostic). **Personal
  working files** are on `/srv/nori` (`@srv-nori` subvolume; `~/Documents` etc.
  symlink there; Samba tailnet-only). `/srv/share` is storage. Secrets
  (`~/.ssh`, `~/.config/sops` — the age master, also derivable from `/etc/ssh`
  host keys — `~/.config/gh`, `~/.claude.json`) stay in `$HOME`, never on `/srv`.

## How to run / build anything (the #1 friction)

`node` / `pnpm` are **not** on PATH. Don't fight it:

- **Per-repo dev shell** — each substantial repo has its own self-contained
  `flake.nix` (own nixpkgs lock; *not* coupled to the private homelab flake).
  `cd` in and `direnv` auto-loads it (it's enabled machine-wide; `direnv allow`
  once per repo), or run `nix develop`.
- **Ad-hoc tool** — `nix shell nixpkgs#<pkg> -c <cmd>` / `nix run nixpkgs#<pkg>`.
- **Untrusted dev commands** (`pnpm install` / test / build) — run through
  `scripts/dev-sandbox.sh` (bubblewrap: repo RW, nix store RO, `$HOME` secrets
  masked, env scrubbed, network droppable with `--no-net`) in the pnpm repos.
- **`pagu-box`** — cross-platform sandboxed launcher (Linux: bubblewrap; macOS:
  sandbox-exec). Process-agnostic — wraps any command, not just agents. Profiles
  (`default | strict | paranoid | loose`) trade off ergonomics vs. lockdown.
  Repo: github:phibkro/pagu-box. Workstation also ships thin aliases
  `claude-box` (= `pagu-box --profile=strict ... -- claude`) and
  `opencode-box` for muscle memory; both consolidate onto pagu-box internally.

## Per-project cheat-sheet

| repo | nature | gate / health command | quirks |
| --- | --- | --- | --- |
| **pagu** | Deno; local-first security agent (the 6 invariants) | `deno task ci` | runner spawns bwrap (the cage); security-critical; flake = deno + git-cliff + bwrap |
| **bang-lang** | TS compiler → Effect; pnpm monorepo (core / compiler / cli) | `pnpm test` (≈322) | correctness-critical; `README.md` is a symlink to `CLAUDE.md` |
| **occupational-health** | TS pnpm-monorepo platform (Effect / @effect/rpc, 8 packages) | per-package tests (a known workspace cycle breaks `vp run test -r`) | **commit from inside `nix develop`** — the `.vite-hooks` pre-commit hook needs `node`; dependency-cruiser enforces module boundaries |
| **homelab** | Nix flake — the machine itself | `nix flake check` (guard derivations) + `just test` (runtime introspection — `docs/RUNTIME_TESTS.md`) | changes need `nh os switch` to apply; direnv / pagu-box / samba / disko live here; `just preview → test → pending → rebuild` iteration loop |
| **pagu-box** | Cross-platform shell-script sandbox (no test suite yet) | `nix build .#pagu-box` | bwrap (linux) + sandbox-exec (darwin); profile system; consumed by homelab via flake input |
| **snowy** | Rust + GTK4 + libadwaita settings panel for Stylix-backed HM/desktop config (M0 done, M1 = read Stylix config) | `just dev` (inside `nix develop`) | Companion to homelab's iteration trio — GUI over the `just show-option/set/preview/rebuild` loop. Stylix-only by design. `github:phibkro/snowy` |
| **phibkro.org/** | app fleet (drinks, filmder, finnbydel, heim) | per-app | these *do* consume the homelab `lab.lib.mkDevShell` profile (the per-project-flake rule is for the substantial standalone repos, not this fleet) |
| beatopia, rice-registry | see each repo's own entrypoint | — | less load-bearing; orient from their `README`/`CLAUDE.md` |

## Conventions (the "amnesiac-team" SDLC)

Every session is a fresh teammate; docs are the transmission medium. Each repo
opens with a docs-map entrypoint (`CLAUDE.md` / `AGENTS.md`) → tiered docs
(CONTEXT / ROADMAP / CONCEPTS / INVARIANTS / `decisions/`). **Read the entrypoint
first.**

- **Commit directly to `main`** (solo dev; no feature branches). Conventional
  Commits, why-focused body, `Co-Authored-By` trailer. Pushing is the operator's
  call.
- **Definition of done** = the repo's gate green (above) + touched docs updated +
  deferred items written down, not dropped.
- **Verify by running the real thing**, especially for security-adjacent work —
  and **ground claims in the code, not in review prose** (a review this machine
  ran once confabulated a "casing bug" that two distinct types' definitions
  disproved; the code is the source of truth).
- **Multi-repo work**: delegate per-repo to parallel agents with precise,
  evidence-bound specs; review their commits. Don't fan out beyond what you'll
  verify.

## Gotchas worth inheriting

- A bare `pnpm install` **outside** the dev-sandbox dumps a ~600 MB content store
  at `/srv/share/.pnpm-store` (pnpm picks the drive root). Use the dev shell /
  sandbox, or clean it after. `node_modules` + `.sandbox-home/` are gitignored,
  regenerable cruft — safe to delete to reclaim space.
- `nh os switch` mounts only subvolumes that already **exist** — create a new
  btrfs subvolume *before* declaring its mount, or the switch fails to mount it.
- The Samba shares are **tailnet-only, single-user `nori`**. `/srv/nori` has a
  recursive dotfile veto (`veto files = /.*/`) as a secret backstop — but it only
  catches dot-prefixed *names*, so never store non-dot secret files there either.
