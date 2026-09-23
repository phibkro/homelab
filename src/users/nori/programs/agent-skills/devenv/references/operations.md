# Operations

Use this reference for services, processes, supervisors, ports, and containers.

## Select a service or process

| Need | Use | Why |
|---|---|---|
| A supported database or server with declarative settings | `services.NAME` | The service module creates its process and data setup. |
| A custom command with a lifetime | `processes.NAME` | The process graph owns start, stop, readiness, and restart. |
| A one-shot operation | `tasks.NAME` | The task graph owns ordering and status. |
| A reproducible image or isolated runtime | `containers.NAME` | The container output owns image build and execution. |

A service is a higher-level process. Do not define a second process for a
service that already has a module.

## Configure a service

```nix
{ pkgs, ... }:
{
  services.postgres = {
    enable = true;
    package = pkgs.postgresql_15;
    initialDatabases = [ { name = "app"; } ];
    initialScript = "CREATE EXTENSION IF NOT EXISTS pgcrypto;";
  };
}
```

Service modules can expose package, settings, port, bind address, data
directory, initial databases, extensions, and initialization script fields.
Read the service's generated options. The supported service list is volatile.
Use [the service catalog](https://devenv.sh/services/) instead of copying it
into a local module.

`services.postgres.enable` creates the `processes.postgres` process. Start and
inspect it through the process lifecycle:

```sh
devenv up
devenv processes list
devenv processes logs postgres
devenv processes status postgres
devenv down
```

Run a readiness check before a dependent task or test. Read the process output
when a service does not become ready.

## Configure a process

```nix
{ ... }:
{
  processes.api = {
    exec = "./bin/api";
    cwd = "./backend";
    watch.paths = [ ./backend ];
    ports.http.allocate = 8080;
    restart.on = "on_failure";
  };
}
```

In v2.2.2, `cwd` has type `null or string`. `watch.paths` is a list of Nix paths,
`ports.NAME.allocate` is the base port for allocation, and `restart.on` accepts
`"never"`, `"always"`, or `"on_failure"`. The process surface also includes
`exec`, `env`, `listen`, `ready`, `start.enable`, `before`, and `after`.
The exact option schema belongs to the generated option reference. Use a
declared port or a readiness probe when another task needs a service.

Start a selected process or the complete graph:

```sh
devenv up api
devenv processes up api --mode before
devenv processes wait --timeout 120
devenv processes restart api
devenv processes stop api
devenv down
```

Use `devenv up -d` only when the process must outlive the calling terminal. Use
`devenv processes attach` only when that command exists in the exact installed
version. Read [version-boundaries.md](version-boundaries.md) for post-2.2.2
process manager changes.

## Process supervision rules

- Give every long-running process one clear owner.
- Use `after` and `before` for dependency order.
- Use `ready` or `listen` when readiness matters.
- Use `watch` only for paths that must restart the process.
- Use `devenv processes logs NAME` before changing a failed process.
- Stop background processes with `devenv down` or the exact process command.
- Keep ports in configuration, not in shell comments or hidden scripts.

Process-manager behavior can differ between native and external managers. Read
the supported manager list and the generated options for the pinned version.

## Build and run a container

The built-in container names are `shell` and `processes`. Custom containers use
`containers.NAME` and can set fields such as `copyToRoot`, `entrypoint`,
`startupCommand`, `registry`, and `defaultCopyArgs`.

Use this bounded flow:

1. Read `containers.NAME` and the packages, files, and processes it includes.
2. Run `devenv container build NAME`.
3. Run `devenv container run NAME` locally.
4. Inspect the image behavior and logs.
5. Ask for operator authority before `devenv container copy NAME` to a registry.

Container configuration can reuse the same packages and processes as the
local environment. A container is not a replacement for a local shell. The
official devenv flake gates its `devenv-image` output to Linux.

## Source and safety

- [Services](https://devenv.sh/services/)
- [Processes](https://devenv.sh/processes/)
- [v2.2.2 process docs](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/processes.md)
- [Containers](https://devenv.sh/containers/)
- [v2.2.2 container docs](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/containers.md)
- [Generated options](https://devenv.sh/reference/options/)
- [v2.2.2 CLI source](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/devenv/src/cli.rs)

A registry copy or push changes external state. Ask before that operation. Do
not put registry credentials or secret values in `devenv.nix`.
