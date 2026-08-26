# Automation

Use this reference for scripts, shell entry, generated files, git hooks, tasks,
and tests.

## Select the automation form

| Need | Use | Lifetime and control |
|---|---|---|
| A command that a developer calls | `scripts.NAME` | The command exists in the activated environment. |
| Small output or setup at shell entry | `enterShell` | Runs when the shell activates. |
| A repeatable operation with order, inputs, or cache | `tasks.NAME` | The task graph controls dependencies and status. |
| A command that accepts a long-running lifetime | `processes.NAME` | Read [operations.md](operations.md). |
| An environment acceptance journey | `enterTest` and `devenv test` | Processes start for the test and stop after it. |
| A commit-time check | `git-hooks.hooks.NAME` | The git hook runner invokes the configured hook. |

## Add a script

```nix
{ pkgs, ... }:
{
  packages = [ pkgs.curl ];
  scripts.health-check.exec = ''
    curl --fail http://127.0.0.1:8080/health
  '';
}
```

Use a script for a command that does not need graph ordering. Run it with
`devenv shell -- health-check`. Keep the script body small and make failures
non-zero.

## Use shell entry and generated files

`enterShell` runs shell code after activation. Use it for a short message or a
small local setup. Use a task when the setup needs ordering, status, inputs, or
parallel work.

`files` creates declared files from the evaluated configuration. Use it for
non-secret configuration that the application needs at a known path. Do not put
secret values in a `files` declaration.

The environment surface uses `env.NAME`. A dotenv file uses `dotenv.enable`
and `dotenv.filename`. Read [integrations.md](integrations.md) before loading
values from a dotenv file.

## Define and run a task

```nix
{ ... }:
{
  tasks = {
    format = {
      description = "Format the source tree";
      exec = "formatter";
    };
    check = {
      after = [ "format" ];
      exec = "check-command";
    };
  };
}
```

Tasks already run inside the activated devenv environment; do not nest
`devenv shell` in a task.

Run a named task after you read its help:

```sh
devenv tasks run check --mode before
```

Use `after` and `before` for graph order. Use `status` and `outputs` for task
state. Use `execIfModified` or declared inputs when a task must rerun after a
source change. Use `--input KEY=VALUE` or `--input-json JSON` for run-time
values. Use `devenv tasks list` to inspect names and descriptions.

A task can depend on a process readiness node. Keep that dependency explicit.
Read [operations.md](operations.md) when the task starts or waits for a
process.

## Configure git hooks

First add the official `git-hooks.nix` input:

```sh
devenv inputs add git-hooks github:cachix/git-hooks.nix --follows nixpkgs
```

This setup mutates `devenv.yaml`; resolving the input writes or updates
`devenv.lock`. Treat the command and its resolution as a YAML/lock mutation.
Run it only after an explicit request and operator authority. The command also
requires the project's `nixpkgs` input.

The resulting input shape is:

```yaml
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
  git-hooks:
    url: github:cachix/git-hooks.nix
    inputs:
      nixpkgs:
        follows: nixpkgs
```

Then configure hooks in `devenv.nix`:

```nix
{ ... }:
{
  git-hooks.hooks = {
    shellcheck.enable = true;
    nixfmt-rfc-style.enable = true;
  };
}
```

The hook options come from the valid, pinned `git-hooks.nix` input. Read its
[official source](https://github.com/cachix/git-hooks.nix) and the generated
option reference before selecting a hook. Install the configured hooks through
the generated `devenv:git-hooks:install` task. A project without `.git` warns
and skips hook installation only after this input is valid. Do not replace a
repository's existing hook policy without reading it first.

## Run an environment test

```nix
{ ... }:
{
  enterTest = ''
    wait_for_port 8080
    curl --fail http://127.0.0.1:8080/health
  '';
}
```

Run the test with:

```sh
devenv test --no-tui
```

`devenv test` starts the configured processes, runs `enterTest`, and stops the
processes. Use the `ci` alias only when the project accepts that spelling. The
`wait_for_port` helper waits for a service or process port. Use the smallest
journey that proves the requested behavior.

## Bounded workflow

1. Read the existing scripts, tasks, hooks, and test entry points.
2. Run `devenv tasks list` when task names are unclear.
3. Add one named operation to the owning section.
4. Run the named script or task with `devenv shell --` or `devenv tasks run`.
5. Run `devenv test --no-tui` when the change affects the environment journey.
6. Read the output and process logs before changing the graph again.

## Sources

- [Scripts](https://devenv.sh/scripts/)
- [Tasks](https://devenv.sh/tasks/)
- [v2.2.2 task docs](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/tasks.md)
- [Tests](https://devenv.sh/tests/)
- [v2.2.2 test docs](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/tests.md)
- [Git hooks](https://devenv.sh/git-hooks/)
- [Files and variables](https://devenv.sh/files-and-variables/)
- [Dotenv](https://devenv.sh/integrations/dotenv/)
