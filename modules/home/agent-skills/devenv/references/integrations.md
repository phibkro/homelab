# Integrations

Use this reference for Cachix, CI, direnv, shell hooks, editors, LSP, MCP,
and cloud behavior.

## Select an integration

| Need | Use | Authority or boundary |
|---|---|---|
| Pull or push Nix substitutes | `cachix.enable`, `cachix.pull`, `cachix.push` | Pull is local setup. Ask before a push. |
| Load a shell on directory entry | `devenv direnvrc` and `use devenv` | `.envrc` changes shell activation. Ask before changing it. |
| Load a shell without direnv | `devenv hook SHELL`, `devenv allow`, `devenv revoke` | `allow` and `revoke` change activation state. Ask first. |
| Run checks in GitHub Actions | `devenv shell -- CMD` or `devenv test` | Use the repository's CI policy and lockfile. |
| Configure editor Nix support | `devenv lsp` or `devenv lsp --print-config` | The command starts or configures nixd. |
| Give an AI client devenv search | `devenv mcp` or `devenv mcp --http[=PORT]` | MCP exposes the documented search and inspection surface. |
| Use a hosted environment | `config.cloud.enable` and `config.cloud.ci.github` | Private-beta/cloud-runtime-only, not the normal local module graph. Ask before use. |

## Configure Cachix

A project can configure pull and push behavior:

```nix
{ ... }:
{
  cachix = {
    enable = true;
    pull = [ "devenv" ];
    push = "my-cache";
  };
}
```

The exact cache option schema belongs to the generated option reference. The
CLI reads `CACHIX_AUTH_TOKEN` for authentication. SecretSpec can supply a token
when its integration is enabled. Do not put a token in `devenv.nix` or
`devenv.yaml`.

Pulling a public substitute is part of normal realization. Ask before setting
`cachix.push` or otherwise publishing paths. A push can expose source-derived
artifacts and creates external cache state.

## Secrets and dotenv

Use `secretspec.toml` with `secretspec.enable`, `secretspec.provider`, and
`secretspec.profile` for runtime secret resolution. The CLI exports
`SECRETSPEC_PROVIDER` and `SECRETSPEC_PROFILE` when configured. Keep secret
values outside `devenv.nix`, `devenv.yaml`, and committed files.

Use `dotenv.enable` and `dotenv.filename` for non-secret environment input.
The dotenv integration is deprecated for secret custody because it can copy
the entire file into the Nix store. Prefer SecretSpec for secrets.

Read the [SecretSpec integration](https://devenv.sh/integrations/secretspec/)
and [dotenv integration](https://devenv.sh/integrations/dotenv/) for the exact
provider and file options.

## Use direnv

Print the integration code and place it in the repository's `.envrc` only when
the operator approves the file change:

```sh
devenv direnvrc
eval "$(devenv direnvrc)"
use devenv
```

The `use devenv` call evaluates the project and exports its environment. Read
the current `.envrc` before changing it. Do not use a hidden second activation
path when the repository already uses a different direnv policy.

## Use native shell hooks

The public hook command accepts `bash`, `zsh`, `fish`, and `nu`:

```sh
eval "$(devenv hook bash)"
eval "$(devenv hook zsh)"
devenv hook fish | source
devenv hook nu
```

Install the shell-specific form in the user's shell configuration only with
operator authority. `devenv allow` and `devenv revoke` change the local
activation trust state. They are not read-only inspection commands.

## Use editors and LSP

`devenv lsp` starts the nixd language server with configuration derived from the
project. Use `devenv lsp --print-config` when an editor needs a generated config
without starting the server.

The official editor pages cover VS Code, IntelliJ or PyCharm, and Zed. An
editor integration consumes the same environment and Nix modules. It does not
create a separate package or language policy.

## Use GitHub Actions

A bounded CI flow is:

1. Check out the repository.
2. Install Nix and the project-approved devenv CLI.
3. Restore the project lockfile and approved binary cache settings.
4. Run `devenv shell -- COMMAND` or `devenv test --no-tui`.
5. Publish only artifacts that the operator or CI policy authorizes.

Use the project's existing Actions and cache policy. Do not update inputs or
push to Cachix while diagnosing a failed job unless that effect is requested.
A flake project can use `nix develop`; read [composition.md](composition.md)
for the boundary between flake and dedicated CLI operation.

## Use MCP

Start the documented server in stdio mode:

```sh
devenv mcp
```

Use HTTP only when the client requires it:

```sh
devenv mcp --http=8080
```

The official MCP integration exposes package and option search. Claude Code
can receive generated hooks, commands, agents, and MCP server configuration
through `claude.code.*` options. Read [version-boundaries.md](version-boundaries.md)
before using current-main Claude agent options.

Do not treat MCP as arbitrary shell access. Keep the AI client's tool policy
narrow and review generated configuration before installing it.

## Cloud and remote boundary

The following is a cloud-runtime illustration only. Do not evaluate this
`config.cloud.*` syntax in a local v2.2.2 module graph:

```nix
{ config, lib, ... }:
{
  services.postgres.enable = !config.cloud.enable;
  services.redis.enable = config.cloud.enable;

  git-hooks.fromRef = lib.mkIf config.cloud.enable null;
}
```

`config.cloud.enable` can select cloud-specific services. The cloud CI example
uses `config.cloud.ci.github` with fields such as `base_ref`, `ref`, and
`branch`. These values are private-beta/cloud-runtime-only.

`cloud.devenv.sh` is in private beta. Ask before using it. The official
navigation does not document a generic SSH remote-environment CLI. Do not
present SSH as a devenv remote backend.

## Sources

- [Binary caching](https://devenv.sh/binary-caching/)
- [Cachix configuration](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/docs/src/binary-caching.md)
- [Direnv integration](https://devenv.sh/integrations/direnv/)
- [Auto activation](https://devenv.sh/auto-activation/)
- [Editor support](https://devenv.sh/editor-support/)
- [LSP](https://devenv.sh/lsp/)
- [GitHub Actions](https://devenv.sh/integrations/github-actions/)
- [MCP](https://devenv.sh/mcp/)
- [Claude Code](https://devenv.sh/integrations/claude-code/)
- [Cloud](https://devenv.sh/cloud/)
- [v2.2.2 CLI source](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/devenv/src/cli.rs)
