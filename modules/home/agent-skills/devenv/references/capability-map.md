# devenv capability map

This map covers the public devenv surface at `v2.2.2`. The stable label means
that the `v2.2.2` source or documentation names the feature. Current `main`
features are not part of this baseline. Read
[version-boundaries.md](version-boundaries.md) before using a moving feature.

## Lifecycle

A devenv project has three common files:

- `devenv.nix` defines the Nix module configuration.
- `devenv.yaml` defines inputs, imports, and selected CLI behavior.
- `devenv.lock` pins the resolved inputs.

The usual lifecycle is:

1. Scaffold or inspect the project.
2. Resolve and evaluate inputs and modules.
3. Build or substitute the shell and its outputs.
4. Activate the shell.
5. Start processes and services when a command needs them.
6. Run scripts, tasks, or tests.
7. Inspect output and stop owned processes.

The dedicated CLI can also load a filesystem or flake source with `--from`. A
project can embed the devenv module in a Nix flake. These paths share the Nix
module model but have different lock and invocation rules.

## Public CLI inventory

The inventory below is the `v2.2.2` public command surface. Always run the
installed command with `--help` before use because the project can pin a
specific CLI release.

### Top-level commands

| Command | Function |
|---|---|
| `devenv help [COMMAND]` | Print help for the command or subcommand. |
| `devenv init [TARGET] [--include-envrc]` | Scaffold `devenv.yaml`, `devenv.nix`, `.gitignore`, and optionally `.envrc`. |
| `devenv generate` | Generate `devenv.yaml` and `devenv.nix` with AI. |
| `devenv shell [CMD] [ARGS...]` | Activate the environment, or run a command in it. |
| `devenv update [NAME]` | Resolve inputs and update `devenv.lock`. |
| `devenv search NAME` | Search nixpkgs packages and options. |
| `devenv info` | Print environment information. `show` is an alias. |
| `devenv up [PROCESSES...]` | Start processes in the foreground. |
| `devenv down` | Stop processes that run in the background. |
| `devenv processes ...` | Manage processes with the nested commands below. |
| `devenv tasks ...` | Run or list tasks with the nested commands below. |
| `devenv test [--override-dotfile]` | Run tests. `ci` is an alias. |
| `devenv container ...` | Build, copy, or run a container. |
| `devenv inputs ...` | Add an input with the nested command below. |
| `devenv changelogs` | Show relevant changelogs. |
| `devenv repl` | Open an interactive environment for configuration inspection. |
| `devenv gc` | Delete previous shell generations. |
| `devenv build ATTR...` | Build attributes from `devenv.nix`. |
| `devenv eval ATTR...` | Evaluate attributes and return JSON. |
| `devenv direnvrc` | Print the direnv integration script. |
| `devenv version` | Print the devenv version. |
| `devenv mcp [--http[=PORT]]` | Launch the MCP server in stdio or HTTP mode. |
| `devenv lsp [--print-config]` | Start nixd for `devenv.nix`, or print its config. |
| `devenv hook SHELL` | Print an auto-activation hook for `bash`, `zsh`, `fish`, or `nu`. |
| `devenv allow` | Allow auto-activation for the current directory. |
| `devenv revoke` | Revoke auto-activation for the current directory. |

### Nested process commands

`devenv processes` has these public subcommands:

- `up [PROCESSES...]`, with `--detach`, `--mode single|before|after|all`, and strict
  port flags;
- `attach`;
- `down`;
- `wait [--timeout SECONDS]`;
- `list`;
- `status NAME`;
- `logs NAME [--lines N] [--stdout|--stderr]`;
- `restart NAME`;
- `start [NAME] [--detach]`; and
- `stop [NAME]`;
- `help [COMMAND]`.

### Nested task commands

`devenv tasks` has these public subcommands:

- `run [TASKS...]`, with `--mode single|before|after|all`, `--show-output`, repeated
  `--input KEY=VALUE`, and `--input-json JSON`; and
- `list`, with `--json` for machine-readable output;
- `help [COMMAND]`.

### Nested container and input commands

`devenv container` has:

- `build NAME`;
- `copy NAME [--registry REGISTRY] [--copy-args ...]`; and
- `run NAME [--copy-args ...]`;
- `help [COMMAND]`.

`devenv inputs` has:

- `add NAME URI [--follows INPUT]`;
- `help [COMMAND]`.

### Global options

These options apply to the relevant commands:

| Group | Options |
|---|---|
| Nix execution | `--max-jobs`, `--cores`, `--system`, `--impure`, `--no-impure`, `--offline`, `--nix-option NAME VALUE`, `--nix-debugger`. |
| Evaluation and task cache | `--eval-cache`, `--no-eval-cache`, `--refresh-eval-cache`, `--refresh-task-cache`. |
| Shell | `--clean [ENV...]`, repeated `--profile NAME`, `--reload`, `--no-reload`, `--shell bash|zsh|fish|nu`. |
| SecretSpec | `--secretspec-provider NAME`, `--secretspec-profile NAME`. |
| Inputs and options | `--from SOURCE`, `--override-input NAME URI`, `--option OPTION:TYPE VALUE`. Types include `string`, `int`, `float`, `bool`, `path`, `pkg`, and `pkgs`. A `pkgs!` option replaces the list. |
| Tracing | Repeated `--trace-to [format:]destination`. Formats include `json`, `pretty`, `full`, `otlp-grpc`, `otlp-http-protobuf`, and `otlp-http-json`. |
| Output | `--verbose`, `--quiet`, `--tui`, and `--no-tui`. |

### Hidden and internal commands

The CLI source also contains these hidden commands:

- `assemble`;
- `print-dev-env [--json]`;
- `direnv-export`;
- `print-paths`;
- `hook-should-activate`; and
- `daemon-processes CONFIG_FILE`.

The hidden global `--backend` option selects an internal Nix backend type. Do
not teach these commands or this option as normal user workflows.

### Official CLI sources

- [v2.2.2 CLI source](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/devenv/src/cli.rs)
- [v2.2.2 README](https://github.com/cachix/devenv/blob/v2.2.2/README.md)

## Capability matrix
| Concern | Exact surface | Lifecycle stage | Composability boundary | Official evidence |
|---|---|---|---|---|
| Bootstrap, evaluation, and activation | `devenv.nix`, `devenv.yaml`, `devenv.lock`, `init`, `shell`, `update`, `info` | Scaffold -> resolve -> evaluate -> build -> activate | All supported concerns enter one module graph and shell lifecycle. | [Basics](https://devenv.sh/basics/), [YAML options](https://devenv.sh/reference/yaml-options/), [CLI](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/devenv/src/cli.rs) |
| Packages and libraries | `packages`, `pkgs`, `devenv search`, `nixpkgs.*` policy, `multiverse` | Declare -> substitute or build -> add executables, libraries, and headers | Use a package for general tools. Use overlays or inputs to extend `pkgs`. | [Packages](https://devenv.sh/packages/), [v2.2.2 packages source](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/packages.md), [Overlays](https://devenv.sh/overlays/) |
| Language modules | `languages.LANG.enable` and language-specific modules | Select toolchain -> install packages -> activate language setup | Use a language module for supported toolchain behavior. Add ordinary packages for extra tools. | [Language catalog](https://devenv.sh/languages/), [v2.2.2 language docs](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/languages/index.md), [Option reference](https://devenv.sh/reference/options/) |
| Services | `services.SERVICE.enable` and each service module | Configure -> create data and process state -> start -> probe -> stop | Use a service for a supported database or server interface. Use a process for a custom command. | [Services](https://devenv.sh/services/), [Supported services](https://devenv.sh/services/#supported-services), [Option reference](https://devenv.sh/reference/options/) |
| Processes and supervisors | `processes.NAME`, `up`, `down`, and `processes ...` | Build the process graph -> start a supervisor -> manage ports, readiness, logs, watches, and restarts | Services are higher-level process definitions. Tasks can depend on process readiness. | [Processes](https://devenv.sh/processes/), [v2.2.2 process docs](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/processes.md) |
| Tasks | `tasks.NAME`, `tasks run`, `tasks list`, `--mode`, `--input`, `--input-json` | Resolve graph -> use status and cache -> run dependencies and task -> record outputs | Use a task for ordered or cached automation. Tasks can start or wait for processes. | [Tasks](https://devenv.sh/tasks/), [v2.2.2 task docs](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/tasks.md) |
| Scripts, environment, and files | `scripts.NAME`, `env.NAME`, `enterShell`, `enterTest`, `files`, `dotenv.*` | Materialize environment and files -> run shell-entry actions -> run scripts or commands | Use `enterShell` for small entry output. Use tasks for dependencies and repeatable setup. | [Scripts](https://devenv.sh/scripts/), [Files and variables](https://devenv.sh/files-and-variables/), [Basics](https://devenv.sh/basics/), [Dotenv](https://devenv.sh/integrations/dotenv/) |
| Git hooks | `git-hooks.hooks.*`, generated git-hooks tasks | Evaluate hook module -> install -> run on commit or by task | The git-hooks.nix input supplies hook implementations. Hooks can use packages and scripts. | [Git hooks](https://devenv.sh/git-hooks/), [git-hooks.nix](https://github.com/cachix/git-hooks.nix) |
| Tests | `devenv test`, alias `ci`, `enterTest`, `wait_for_port` | Build shell -> start processes -> run test script -> stop processes -> report | Use tests for environment acceptance. Use tasks for reusable non-test automation. | [Tests](https://devenv.sh/tests/), [v2.2.2 tests source](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/tests.md) |
| Profiles | `profiles.NAME.module`, `--profile NAME`, `devenv.yaml profile` | Select profile -> merge module -> activate variant | Use a profile for a variant. Use imports for shared structure across projects. | [Profiles](https://devenv.sh/profiles/), [v2.2.2 profiles source](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/profiles.md) |
| Monorepos, imports, modules, inputs, and overlays | YAML `imports`; Nix `imports`; `inputs.NAME.*`; `devenv inputs add`; `--override-input`; `lib.mkIf`; `lib.mkMerge` | Resolve root and imported files -> resolve inputs -> merge modules -> evaluate | Use imports for shared project configuration. Use inputs for versioned external sources. Use overlays to extend package sets. | [Composition](https://devenv.sh/composing-using-imports/), [Inputs](https://devenv.sh/inputs/), [Overlays](https://devenv.sh/overlays/) |
| Secrets and dotenv | `secretspec.toml`, `secretspec.enable`, `.provider`, `.profile`, `secretspec.cachix_auth_token`, `dotenv.*` | Declare names -> resolve at runtime -> inject into the required command or process | Use SecretSpec for secret custody. Treat dotenv as configuration input, not secret storage. | [SecretSpec integration](https://devenv.sh/integrations/secretspec/), [Dotenv integration](https://devenv.sh/integrations/dotenv/), [SecretSpec](https://secretspec.dev/) |
| Containers | `containers.shell`, `containers.processes`, `containers.NAME.*`, `container build|copy|run` | Derive image -> build -> copy to registry or run | Use the environment for local execution. Use a container for an image or isolated runtime artifact. | [Containers](https://devenv.sh/containers/), [v2.2.2 container docs](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/containers.md) |
| Cachix and binary caches | `cachix.enable`, `cachix.pull`, `cachix.push`, `CACHIX_AUTH_TOKEN`, Nix substituters and trusted keys | Configure -> authenticate -> pull substitutes -> optionally push realized paths | Cache behavior follows the exact lock, system, and cache visibility. | [Binary caching](https://devenv.sh/binary-caching/), [v2.2.2 cache docs](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/binary-caching.md) |
| Nix and flake integration | `devenv.lock`, `devenv.flakeModules.default`, `devenv.lib.mkShell`, `devShells`, `nix develop` | Pin -> evaluate -> expose dev shell or output -> update intentionally | Use dedicated CLI for a plain devenv project. Use flake integration when the project owns a flake. | [Using flakes](https://devenv.sh/guides/using-with-flakes/), [Pinning](https://devenv.sh/pinning/), [v2.2.2 flake](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/flake.nix) |
| CI | `devenv shell -- CMD`, `devenv test`, optional Nix and Cachix Actions | Checkout -> install Nix/devenv -> enter shell -> run checks and tests -> publish approved artifacts | CI uses the same configuration and lockfile as local work. | [GitHub Actions](https://devenv.sh/integrations/github-actions/), [Using flakes](https://devenv.sh/guides/using-with-flakes/) |
| Direnv, shell, editor, and LSP | `devenv direnvrc`, `use devenv`, `devenv hook SHELL`, `allow`, `revoke`, `devenv lsp` | Install adapter -> enter project -> activate or reload -> deactivate on exit | Direnv and native hooks are alternate activation paths. LSP emits nixd configuration. | [Direnv](https://devenv.sh/integrations/direnv/), [Auto activation](https://devenv.sh/auto-activation/), [VS Code](https://devenv.sh/editor-support/vscode/), [LSP](https://devenv.sh/lsp/) |
| AI and MCP | `devenv mcp`, `devenv mcp --http`, MCP package and option search, Claude Code integration | Launch server -> expose inspection/search tools -> configure an AI client | MCP adapts the evaluator and search surface. It does not grant arbitrary shell authority. | [MCP](https://devenv.sh/mcp/), [Claude Code](https://devenv.sh/integrations/claude-code/), [v2.2.2 CLI](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/devenv/src/cli.rs) |
| Inspection, debugging, and maintenance | `info`, `search`, `eval`, `build`, `repl`, `lsp --print-config`, `--nix-debugger`, `--verbose`, tracing, process logs/status, `changelogs`, `gc`, cache refresh flags | Inspect -> evaluate or build a selected value -> inspect logs and traces -> remove old generations | These commands inspect the same project configuration. Use `repl` or `eval` instead of guessing option values. | [REPL](https://devenv.sh/repl/), [Garbage collection](https://devenv.sh/garbage-collection/), [CLI source](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/devenv/src/cli.rs) |
| Platforms | `--system`, `nixpkgs.per_platform`, platform conditionals | Select target -> evaluate compatible packages -> build and run | `lib.mkIf` and `pkgs.stdenv` let one module handle platform differences. | [Homepage](https://devenv.sh/), [Cross-platform recipe](https://devenv.sh/recipes/cross-platform/), [v2.2.2 flake](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/flake.nix) |
| Cloud and remote environments | **Private-beta/cloud-runtime-only:** `config.cloud.enable`, `config.cloud.ci.github`, `cloud.devenv.sh` | Opt into the hosted cloud runtime -> evaluate cloud conditionals -> run the cloud environment | Not part of the normal local v2.2.2 module graph. Use only with the cloud runtime. | [Cloud](https://devenv.sh/cloud/) |

## Boundary notes

- The homepage advertises more than 100,000 packages for Linux and macOS,
  x64 and ARM64, and WSL2 support. The `v2.2.2` devenv flake explicitly builds
  `x86_64-linux`, `i686-linux`, `aarch64-linux`, and `aarch64-darwin`; its
  `devenv-image` output is Linux-only.
- `config.cloud.*` syntax is private-beta/cloud-runtime-only. Do not ask a
  local v2.2.2 agent to evaluate it.
- Cloud documentation says that `cloud.devenv.sh` is in private beta.
- The official navigation does not document a generic SSH remote-environment
  CLI. Do not present SSH as a devenv remote backend.
- Do not copy the full language or service option catalogs into this skill.
  Follow the linked generated references for the exact module options.

## Version evidence

- [v2.2.2 release changelog](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/CHANGELOG.md)
- [Current main changelog](https://raw.githubusercontent.com/cachix/devenv/main/CHANGELOG.md)
- [Tag-to-main comparison](https://api.github.com/repos/cachix/devenv/compare/v2.2.2...main)

The comparison and current main changelog are evidence for version boundaries,
not stable `v2.2.2` instructions. Use
[version-boundaries.md](version-boundaries.md) for those differences.
