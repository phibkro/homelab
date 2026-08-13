# Bump the pagu pin (guidance ↔ installed binary)

**What**: homelab's `pagu` flake input pins a *published* revision. Agent
guidance — `modules/home/agent-soul/SOUL.md`, the generated
`~/.codex/AGENTS.md`, and the `pagu` skill installed from
`${inputs.pagu}/skills/pagu` — describes whatever that pin contains. Local pagu
commits are invisible to this machine until the pin moves.

**Why it has a runbook**: the failure is silent and one-directional. Guidance is
edited in the pagu working tree, reads as done, and materialises here only after
a pin bump. Agents then follow instructions the installed binary does not
implement, and the error message is an unhelpful `unknown option`.

## Order

```
1. commit + push pagu            (the source of both the binary and the skill)
2. nix flake lock --update-input pagu     [in homelab]
3. review the lock diff — one input, one revision
4. just rebuild                  (operator-owned; quiesce agents first)
5. smoke: pagu --help · pagu <harness> --help · pagu box --help
```

Steps 1 and 2 are not interchangeable. Bumping the input to an unpushed
revision fails to fetch; editing guidance without step 1 ships a description of
code nobody has.

## What is gated on this

As of 2026-07-25 the pinned revision predates all of the following, so each is
written but not yet live:

| Capability | Guidance that assumes it |
| --- | --- |
| `pagu box` subcommand dispatch | `pagu` skill; global Claude/Codex context |
| bare executable (`pagu claude`, no `--`) | `pagu` skill; global context |
| bare `pagu` prints usage instead of launching Codex | `pagu` skill |
| `--harness` validated at the CLI boundary | — |
| vendored deps + `--cached-only` (hermetic start) | — |

`modules/infra/backup/agent-fix.nix` deliberately calls `pagu-box`, **not**
`pagu box`, for exactly this reason. Move it after the bump, not before —
`pagu box` against the current pin is parsed as a harness name and exits 64,
which would break backup-failure repair at the worst moment.

## Verify the pin actually moved

```sh
nix eval --raw .#nixosConfigurations.workstation.config.home-manager.users.nori.home.file \
  --apply 'f: toString f.".claude/skills/pagu".source'
```

Diff that store path's `SKILL.md` against `/srv/share/projects/pagu/skills/pagu/SKILL.md`.
Identical means the pin carries the guidance agents will read. A difference is
the drift this runbook exists to prevent — the skill is installed for **both**
Claude and Codex from one pinned source (`modules/home/agent-skills/`), so they
cannot disagree with each other, only with the working tree.

## Related

- [ADR-0008](../decisions/0008-agents-launch-directly-inside-pagu.md) — why
  agents launch directly inside pagu.
- [`2026-07-23-pagu-homelab-flake-migration.md`](../specs/2026-07-23-pagu-homelab-flake-migration.md)
  — the frozen migration spec. Its §3 is superseded by ADR-0008 and still needs
  revising.
