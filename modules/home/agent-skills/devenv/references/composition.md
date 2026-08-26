# Composition

Use this reference for profiles, imports, modules, inputs, overlays, and
monorepos.

## Select the composition boundary

| Need | Use | Scope |
|---|---|---|
| A variant of one project | `profiles.NAME.module` and `--profile NAME` | Merge a module for one shell, task, or test run. |
| Shared configuration across projects | `devenv.yaml` `imports` and Nix `imports` | Load a path or an input-provided module. |
| A versioned external source | `inputs.NAME.url` and `devenv.lock` | Pin a repository, flake, or module source. |
| A package-set change | `overlays` or `inputs.NAME.overlays` | Extend or modify `pkgs` for the evaluation. |
| A project with several packages | A monorepo layout plus imports and profiles | Keep one root policy and select local variants. |
| A complete existing Nix flake | `devenv.flakeModules.default` and `devShells` | Embed the devenv module in the flake. |

A profile changes one project configuration. An import shares structure. An
input supplies a pinned source. An overlay changes package resolution. Do not
use one as a replacement for another.

## Add a profile

```nix
{ pkgs, ... }:
{
  profiles = {
    backend.module = {
      services.postgres.enable = true;
      processes.api.exec = "./run-api";
    };
    testing.module = {
      packages = [ pkgs.playwright ];
      env.NODE_ENV = "test";
    };
  };
}
```

Select one or more profiles:

```sh
devenv --profile backend shell
devenv --profile backend --profile testing test --no-tui
```

A project can set `profile` in `devenv.yaml` as its default. Profiles can also
match the user, host, or environment when those profile fields are configured.
Read the [profile reference](https://devenv.sh/profiles/) for the exact
matching fields and priority rules.

## Compose imported configuration

A YAML import can point to a relative path, an absolute path, or an input
reference:

```yaml
imports:
  - ../shared-devenv
  - shared-config
```

A shared directory can provide its own `devenv.nix` and `devenv.yaml`. Nix
modules can import files directly:

```nix
{
  imports = [ ./services.nix ./tooling.nix ];
}
```

Use `lib.mkIf` for conditional values and `lib.mkMerge` for conditional
configuration sections. Keep the base project's policy visible. Avoid hidden
imports that change an unrelated project.

## Add an input

A typical input has these fields:

```yaml
inputs:
  shared-config:
    url: github:example/shared-config
    flake: false
    follows: nixpkgs
    overlays:
      - default
```

The exact input schema includes `url`, `flake`, `follows`, nested `inputs`, and
`overlays`. Run `devenv inputs add NAME URI --follows INPUT` when the operator
has approved a file and lock change. Otherwise edit only when the request
explicitly asks for that mutation.

`devenv update [NAME]` resolves inputs and writes `devenv.lock`. Treat the lock
as a shared reproducibility contract. Do not update it to fix an unrelated
package or evaluation error.

## Monorepo workflow

1. Find the root `devenv.nix`, `devenv.yaml`, and `devenv.lock`.
2. List existing YAML and Nix imports.
3. Identify the package, language, service, or process owner for the requested
   subproject.
4. Reuse an existing module or profile when it has the needed boundary.
5. Add one import, input, or overlay only when that is the real ownership seam.
6. Run `devenv info` from the root and from the requested subproject.
7. Run the subproject command with `devenv shell -- COMMAND`.

Prefer one module graph when concerns share a lifecycle. Separate environments
are valid when subprojects have independent locks, platforms, or lifecycles.

## Flake boundary

Use the dedicated CLI when the project has a plain `devenv.nix`. Use flake
integration when the project already owns a `flake.nix` and needs devenv's
module system as a `devShell` or output. Read
[Using devenv with Nix flakes](https://devenv.sh/guides/using-with-flakes/)
before changing flake outputs.

## Sources

- [Composing with imports](https://devenv.sh/composing-using-imports/)
- [Inputs](https://devenv.sh/inputs/)
- [Overlays](https://devenv.sh/overlays/)
- [Profiles](https://devenv.sh/profiles/)
- [Pinning](https://devenv.sh/pinning/)
- [Using devenv with Nix flakes](https://devenv.sh/guides/using-with-flakes/)
- [v2.2.2 input docs](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/inputs.md)
- [v2.2.2 composition docs](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/composing-using-imports.md)
