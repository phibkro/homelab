# Inspection and debugging

Use this reference when evaluation, activation, package lookup, processes, or
maintenance fail.

## Inspect before changing

```sh
devenv version
devenv info
devenv search NAME
devenv eval packages
devenv build shell
```

Run each command from the project that owns `devenv.nix`. Use `--from SOURCE`
when the configuration lives elsewhere. Use `--option OPTION:TYPE VALUE` for a
single diagnostic override. Do not write that override into the project until
its effect is understood.

`devenv info` summarizes the root, state, environment, packages, scripts, and
processes. `devenv eval` returns JSON for selected attributes. Its operands are
already rooted under the devenv configuration, so use the unqualified operand
`packages`. `devenv build` realizes an attribute. `devenv repl` opens an
interactive Nix environment for inspection.

## Diagnose a failed shell

1. Read `devenv info`.
2. Run `devenv shell --help` and record the shell, profile, and Nix overrides.
3. Run `devenv search NAME` for missing packages or options.
4. Run `devenv eval ATTRIBUTE` for the smallest failing value.
5. Run with `--verbose --no-tui` when the normal output lacks the cause.
6. Use `--nix-debugger` when the failure is a Nix evaluation failure.
7. Use `--refresh-eval-cache` only when stale evaluation state is a credible
   cause.
8. Run the real shell command again.

The cache controls are `--eval-cache`, `--no-eval-cache`,
`--refresh-eval-cache`, and `--refresh-task-cache`. A cache refresh is a local
diagnostic action. It does not replace a source fix.

## Diagnose a process

```sh
devenv processes list
devenv processes status NAME
devenv processes logs NAME --lines 100
devenv processes restart NAME
devenv processes wait --timeout 120
devenv down
```

Read status, readiness, ports, and logs before changing a process declaration.
Use `--stdout` or `--stderr` when one stream hides the failure. Stop a detached
session after the diagnosis.

## Trace an operation

Tracing is disabled by default. Use repeated `--trace-to` destinations when a
structured trace is required:

```sh
devenv --trace-to pretty:stderr info
devenv --trace-to json:file:/tmp/devenv-trace.json eval packages
```

The stable formats are `json`, `pretty`, and `full`. The stable destinations
include `stdout`, `stderr`, and `file:PATH`. OpenTelemetry destinations are
available through the documented `otlp-grpc`, `otlp-http-protobuf`, and
`otlp-http-json` forms. Do not put trace files in a repository unless the
project policy permits them.

## Inspect tasks and tests

Use `devenv tasks list` to list task names. Use
`devenv tasks run NAME --show-output` to expose task output. Run
`devenv test --no-tui` when the environment test path is the failing journey.
Read [automation.md](automation.md) for task and test selection.

## Maintain generations

`devenv changelogs` shows relevant project changes. `devenv gc` deletes previous
shell generations. Run garbage collection only when the operator requests
storage maintenance. Do not use it as the first response to an evaluation
failure.

## Sources

- [REPL](https://devenv.sh/repl/)
- [Garbage collection](https://devenv.sh/garbage-collection/)
- [Processes](https://devenv.sh/processes/)
- [Tasks](https://devenv.sh/tasks/)
- [Tests](https://devenv.sh/tests/)
- [v2.2.2 CLI source](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/devenv/src/cli.rs)
- [Generated options](https://devenv.sh/reference/options/)
