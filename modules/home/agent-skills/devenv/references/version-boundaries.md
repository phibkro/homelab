# Version boundaries

The installed baseline for this skill is `devenv 2.2.2`. The release commit is
 dated 2026-08-13. A feature is stable here only when the `v2.2.2` tag directly
evidences it in source or documentation.

## Version check

Run this before using a feature:

```sh
devenv version
devenv --help
devenv COMMAND --help
```

Then read the matching project configuration, lockfile, and generated option
reference. A current website page is not proof that an installed older CLI
supports the page.

## Stable source set

Use these pinned sources for the stable baseline:

- [v2.2.2 changelog](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/CHANGELOG.md)
- [v2.2.2 CLI source](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/devenv/src/cli.rs)
- [v2.2.2 flake](https://raw.githubusercontent.com/cachix/devenv/v2.2.2/flake.nix)
- [v2.2.2 documentation tree](https://github.com/cachix/devenv/tree/v2.2.2/docs/src)

## Current-main watchlist

The current `main` branch has 142 commits after the `v2.2.2` tag as of this
research. Its changelog labels the unreleased section `2.3.0`. The tag's own
next unreleased heading says `2.2.3`. Treat that heading mismatch as evidence
that release labels and docs can move independently.

The table lists current-main features that require a version check. Do not put
their syntax in a stable workflow until the installed help or tag source proves
it.

| Feature | Evidence | Rule |
|---|---|---|
| Claude Code `claude.code.agent`, agent effort, and proactive-agent configuration | Post-tag commits `81815f8`, `c0cbcc56`, `04015cdb`; [current Claude Code page](https://devenv.sh/integrations/claude-code/) | Treat as current-main only. |
| `dotenv-ng` parser behavior, including newer file syntax, substitution, and reload behavior | Post-tag commit `be80b069`; [current changelog](https://raw.githubusercontent.com/cachix/devenv/main/CHANGELOG.md) | Treat parser details as current-main only. |
| Test runtime and shell closure reporting plus `max_closure_size` | Post-tag commit `d9456325`; [current changelog](https://raw.githubusercontent.com/cachix/devenv/main/CHANGELOG.md) | Treat the metric and limit as current-main only. |
| `processes.NAME.shutdown.signal`, `processes.NAME.shutdown.grace`, and manager capability contracts | Post-tag commits `ba0b1662`, `d9d06f80`, and `70d1a935` | Read the installed generated options before use. |
| Multiverse resolution through the fewest nixpkgs revisions | Post-tag commit `d421a433` | Basic `multiverse.NAME.VERSION` exists in the v2.2.2 package docs. The resolver optimization is newer. |
| New task-list display improvements | Post-tag commit `2dddff7`; [current changelog](https://raw.githubusercontent.com/cachix/devenv/main/CHANGELOG.md) | `devenv tasks list --json` is already present in the tagged v2.2.2 CLI. Treat only post-tag display improvements as current-main, and verify any additional fields. |
| New `devenv info` generation through `nix-flake-lock` | Post-tag commits `b0ccd880` and `e19b5d9c` | Treat generated-info details as current-main only. |
| Current-main process cleanup, attach, and named-start behavior | [current changelog](https://raw.githubusercontent.com/cachix/devenv/main/CHANGELOG.md) and [tag comparison](https://api.github.com/repos/cachix/devenv/compare/v2.2.2...main) | Use only when the installed process help and behavior prove it. |
| Current-main shell-hook and `--from ... allow` behavior | [current changelog](https://raw.githubusercontent.com/cachix/devenv/main/CHANGELOG.md) and [tag comparison](https://api.github.com/repos/cachix/devenv/compare/v2.2.2...main) | Do not infer auto-activation or persistent source binding from a moving page. |

The full post-tag evidence is in the official
[tag-to-main comparison](https://api.github.com/repos/cachix/devenv/compare/v2.2.2...main).
A post-tag commit can be a bug fix rather than a new feature. Use the table only
for behavior that affects an agent workflow.

## Do not mislabel stable features

Some current-main changelog entries restate behavior that the `v2.2.2` tag
already exposes. For example, the pinned CLI source already contains `down`,
process `attach` and `start`, `init --include-envrc`, `--trace-to`, and
`tasks list --json` support. The pinned package docs already contain basic
`multiverse` support. Verify the tag source before placing any of these in the
watchlist as a new feature.

The pinned flake lists these package systems:

- `x86_64-linux`;
- `i686-linux`;
- `aarch64-linux`; and
- `aarch64-darwin`.

It gates `devenv-image` to Linux. The homepage separately advertises packages
for Linux and macOS, x64 and ARM64, plus WSL2. The current-main changelog calls
Intel macOS support a breaking change, but the pinned flake already omits
`x86_64-darwin`. Record this as version skew and verify the installed binary,
not as an unqualified post-2.2.2 claim.

## Private beta and evidence gaps

The official [cloud page](https://devenv.sh/cloud/) says that
`cloud.devenv.sh` is in private beta. Keep cloud behavior outside the stable
local workflow and ask for authority before using it.

The official documentation navigation does not expose a generic SSH
remote-environment CLI. Do not claim that devenv supplies one. SSH can be an
external transport for a user's machine, but that is not a documented devenv
remote backend.

## Upgrade workflow

1. Read the project pin and run `devenv version`.
2. Read `devenv --help` and the command-specific help.
3. Compare the needed option with the pinned tag source.
4. If the option is current-main only, stop and report the version boundary.
5. Ask before changing inputs or `devenv.lock`.
6. Run the real journey only after the exact version supports it.
