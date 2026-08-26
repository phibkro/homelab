# Global devenv skill

Status: frozen for the provider-neutral skill draft

Recorded on: 2026-08-26

## Purpose

Provide one provider-neutral `devenv` skill for agents that work with devenv.sh.
The skill covers the shared evaluator, module graph, lockfile, shell lifecycle,
and CLI. It routes detailed work to concern references.

The canonical source is:

`modules/home/agent-skills/devenv/`

The registry exposes this source through `bothSurfaces` for OMP, Claude Code,
and Codex. Generated `$HOME` projections are not source files and are not
edited by this design.

## Trigger boundary

Load the skill when a request:

- names devenv or devenv.sh;
- works in a repository with `devenv.nix`, `devenv.yaml`, or `devenv.lock`;
- asks to migrate a project to devenv; or
- asks whether devenv can own a development-environment concern.

Do not load it only because a repository uses Nix, flakes, direnv, or generic
development tools.

## Contract

The skill must:

1. inspect repository configuration and lock state before advice or edits;
2. run `devenv version` and the relevant command `--help`;
3. use the exact project and CLI version;
4. prefer `devenv search` and generated option references over recalled syntax;
5. route by concern instead of copying volatile option catalogs;
6. separate stable `v2.2.2` evidence from current-main or private-beta claims;
7. protect secrets and require operator authority for external effects; and
8. verify the real user journey after a change.

## Capability boundary

The map covers bootstrap and activation, packages, language modules, services,
processes, tasks, scripts, environment files, generated files, git hooks, tests,
profiles, imports, modules, inputs, overlays, secrets, dotenv, containers,
Cachix, Nix and flakes, CI, direnv, shell and editor integration, LSP, AI/MCP,
inspection, debugging, maintenance, platforms, and cloud or remote behavior.

The public `v2.2.2` CLI is documented in the capability map. Hidden or internal
commands are listed separately and are not normal agent instructions.

## Version boundary

The stable baseline is behavior directly evidenced by the `v2.2.2` tag. Current
main or post-tag features appear only in `references/version-boundaries.md` and
carry a version-check requirement. Cloud remains private beta. No generic
official SSH remote-environment CLI is claimed.

The website and `main` branch can move ahead of the installed CLI. The skill
must treat a current page as a lead, then confirm the feature against the exact
project version.

## Safety boundary

Agents do not put secret values in configuration or commit them. Agents ask for
operator authority before they:

- push to Cachix or copy or push a container to a registry;
- use cloud.devenv.sh;
- change auto-activation with `devenv allow` or `devenv revoke`; or
- mutate inputs or the lockfile with `devenv init`, `devenv inputs add`, or
  `devenv update`.

Agents can inspect and explain these operations without authority.

## Required source tree

- `modules/home/agent-skills/devenv/SKILL.md`
- `modules/home/agent-skills/devenv/agents/openai.yaml`
- `modules/home/agent-skills/devenv/references/capability-map.md`
- `modules/home/agent-skills/devenv/references/environment-and-toolchains.md`
- `modules/home/agent-skills/devenv/references/automation.md`
- `modules/home/agent-skills/devenv/references/composition.md`
- `modules/home/agent-skills/devenv/references/operations.md`
- `modules/home/agent-skills/devenv/references/integrations.md`
- `modules/home/agent-skills/devenv/references/inspection-and-debugging.md`
- `modules/home/agent-skills/devenv/references/version-boundaries.md`

## Registry contract

Register the directory with the existing `bothSurfaces "devenv"` helper in
`modules/home/agent-skills/default.nix`. Do not add another top-level skill for
packages, services, tasks, Nix, or a provider-specific integration.

## Acceptance

The draft is complete when:

1. every required file exists and the registry points at the canonical directory;
2. `SKILL.md` routes every mapped concern;
3. the public CLI inventory matches installed `2.2.2` help or the `v2.2.2`
   source;
4. links, YAML frontmatter, and agent metadata parse;
5. the focused `default.nix` evaluation passes; and
6. `nix flake check` passes from `homelab` after the focused check.
