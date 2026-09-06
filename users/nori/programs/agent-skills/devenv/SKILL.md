---
name: devenv
description: Use for explicit devenv.sh work, repositories with devenv.nix, devenv.yaml, or devenv.lock, migrations to devenv, or decisions about whether devenv owns a development-environment concern. Do not use only because a repository uses Nix, flakes, direnv, or generic development tools.
---

# devenv

Use one devenv skill for the complete environment lifecycle. Packages,
languages, services, processes, tasks, tests, profiles, inputs, and integrations
share one evaluator, module graph, lockfile, and shell lifecycle.

## Start with the exact project

1. Read the repository instructions and the relevant `devenv.nix`,
   `devenv.yaml`, and `devenv.lock` files.
2. Run `devenv version`.
3. Run help for the command that you will use, such as `devenv shell --help`,
   `devenv tasks run --help`, or `devenv processes --help`.
4. Use the project version. Treat the `v2.2.2` reference in this skill as the
   installed baseline only when the project reports `2.2.2`.
5. Prefer `devenv search NAME` and the generated option references over recalled
   package or module syntax.
6. Choose the smallest relevant reference below.
7. Run the real user journey after the change. Report commands and results.

Normal requested edits to tracked source files remain allowed. Obtain explicit
user request and operator authority before operations that mutate project or
external state: `devenv generate` (external AI plus file writes), `devenv init`,
`devenv inputs add`, `devenv update`, `devenv allow`, `devenv revoke`,
`cachix.push`, `devenv container copy`, cloud use, or `devenv gc`. The first
four can change project files or lock state; `allow` and `revoke` change local
activation trust; cache push and container copy publish external state; cloud
use enters a hosted runtime; and `gc` deletes old generations. Review generated
files from `devenv generate` before accepting them.

## Route by concern

| Request | Read |
|---|---|
| Full feature map, command inventory, or support question | [capability-map.md](references/capability-map.md) |
| Packages, libraries, language modules, or project import | [environment-and-toolchains.md](references/environment-and-toolchains.md) |
| Scripts, `enterShell`, generated files, git hooks, tasks, or tests | [automation.md](references/automation.md) |
| Profiles, imports, modules, inputs, overlays, or monorepos | [composition.md](references/composition.md) |
| Services, processes, supervisors, ports, or containers | [operations.md](references/operations.md) |
| Cachix, CI, direnv, shell hooks, editors, LSP, platforms, cloud, remote, or MCP | [integrations.md](references/integrations.md) |
| Secrets and dotenv files | [integrations.md](references/integrations.md) |
| Nix flakes, outputs, inputs, or dedicated CLI versus flake decisions | [composition.md](references/composition.md) |
| `info`, `eval`, `build`, `repl`, logs, tracing, Nix debugger, or garbage collection | [inspection-and-debugging.md](references/inspection-and-debugging.md) |
| A current website feature, release mismatch, or upgrade question | [version-boundaries.md](references/version-boundaries.md) |

## Selection boundaries

- Use a package for a general executable, library, or header.
- Use a language module for a supported toolchain and its language setup.
- Use a service for a supported database or server interface.
- Use a process for a command with a lifetime, port, readiness probe, or watcher.
- Use a task for ordered or cached automation.
- Use `enterShell` only for small shell-entry output or setup.
- Use `devenv test` and `enterTest` for an acceptance check of the environment.
- Use a profile for a variant selected by profile or host context.
- Use imports and modules for reusable configuration across projects.
- Use SecretSpec for runtime secrets. Do not use dotenv for secret custody.
- Use the dedicated CLI for a plain devenv project. Use flake integration when
  the project already owns a Nix flake and needs a `devShell` or output.
- Use a process environment for local execution. Use a container for an image
  or isolated runtime artifact.

## Safe bounded workflow

1. Inspect the current configuration and lockfile.
2. Record `devenv version` and the required command help.
3. Search the exact package or option.
4. Change the smallest source file that owns the concern.
5. Run the command or test journey that exercises the change.
6. Inspect logs or evaluation output when it fails.
7. Ask before any lock, input, auto-activation, cache, registry, or cloud effect.
8. Load [version-boundaries.md](references/version-boundaries.md) when a moving
   website or `main` branch page supplies the feature.

## Normal public commands

The stable public command families are `help`, `init`, `generate`, `shell`,
`update`, `search`, `info`, `up`, `down`, `processes`, `tasks`, `test`,
`container`, `inputs`, `changelogs`, `repl`, `gc`, `build`, `eval`, `direnvrc`,
`version`, `mcp`, `lsp`, `hook`, `allow`, and `revoke`. Read the capability map
for the complete `v2.2.2` nested inventory. Hidden and internal commands are
not normal agent instructions.
