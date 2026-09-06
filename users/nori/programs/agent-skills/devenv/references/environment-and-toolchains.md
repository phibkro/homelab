# Environment and toolchains

Use this reference for packages, libraries, language modules, and language
project imports. Use the exact CLI and module version in the project.

## Choose a package or a language module

| Need | Use | Reason |
|---|---|---|
| A general executable, library, or header | `packages = [ pkgs.NAME ]` | The package enters the shell closure and PATH. |
| A supported language toolchain | `languages.LANG.enable = true` | The module sets the language tools and setup. |
| An exact toolchain version or channel | Language-specific `version`, `channel`, `package`, or `packages` | The language module owns these options. |
| A historical nixpkgs package | `nixpkgs-multiverse` and `multiverse.NAME.VERSION` | The package comes from a pinned historical revision. |
| A project that must become a Nix output | `languages.LANG.import PATH {}` and `outputs.NAME` | The language importer bridges the project to Nix. |

Read the [package catalog](https://devenv.sh/packages/) and the
[language catalog](https://devenv.sh/languages/) before selecting a name. The
language catalog has more than 50 modules. It changes with the project input.
Use the [generated option reference](https://devenv.sh/reference/options/) for
language-specific fields.

## Add a package

1. Run `devenv search NAME`.
2. Read the exact package and version in the result.
3. Add `pkgs.NAME` to `packages` in `devenv.nix`.
4. Run `devenv shell -- NAME --version` or the smallest useful command.
5. Read the shell output if the command is not available.

Example:

```nix
{ pkgs, ... }:
{
  packages = [
    pkgs.git
    pkgs.jq
    pkgs.libffi
  ];
}
```

`packages` accepts executables, libraries, and headers. `pkgs` comes from the
pinned nixpkgs input. Use an overlay when the project needs a systematic package
change. Read [overlays](https://devenv.sh/overlays/) before adding one.

## Enable a language

```nix
{ ... }:
{
  languages.python.enable = true;
  languages.rust.enable = true;
}
```

Set the version or channel only when the language module documents that field.
Do not assume that one language's fields exist for another language.

Some modules provide package-manager or project import helpers. For example:

```nix
{ config, ... }:
{
  languages.rust.enable = true;
  outputs.rust-app = config.languages.rust.import ./rust-app {};
}
```

Read the module's generated options and its linked language page before using an
import helper. An import can add build inputs and a source path to evaluation.

## Pin a historical package

The `v2.2.2` package docs support this flow:

```sh
devenv inputs add nixpkgs-multiverse github:fzakaria/nixpkgs-multiverse
```

Then use the versioned attribute:

```nix
{ multiverse, pkgs, ... }:
{
  packages = [
    pkgs.git
    multiverse.cmake."3.16.5"
  ];
}
```

`devenv inputs add` changes `devenv.yaml` and later lock state. Ask for
operator authority before running it. A package version is reproducible only
when the relevant input remains pinned.

## Search and inspect

Use `devenv search NAME` for package and option names. Use `devenv eval` for a
small attribute that you need to inspect. Use `devenv info` to see the resolved
environment summary. Use `devenv shell -- COMMAND` to exercise the real shell
without opening an interactive session.

If a package is missing, read the search result and the nixpkgs policy options.
These options include `nixpkgs.allow_unfree`,
`nixpkgs.allow_broken`, `nixpkgs.allow_unsupported_system`,
`nixpkgs.permitted_insecure_packages`, and platform-specific configuration.
Do not enable a broad policy when a package-specific policy exists.

## Sources

- [Packages](https://devenv.sh/packages/)
- [v2.2.2 package docs](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/packages.md)
- [Language catalog](https://devenv.sh/languages/)
- [v2.2.2 language docs](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/languages/index.md)
- [Generated option reference](https://devenv.sh/reference/options/)
- [Overlays](https://devenv.sh/overlays/)
- [Outputs](https://devenv.sh/outputs/)
