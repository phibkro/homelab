<!-- generated-by: foundry@v1 -->
# foundry profile v1

Single source for project-conventions boilerplate
(CONVENTIONS-RECONCILIATION.md §3; contract recorded in
docs/PROJECTS.md, "Project conventions contract", 2026-08-24).

| File                   | Emitted to repo root as    | Notes                                              |
|------------------------|----------------------------|----------------------------------------------------|
| `.oxlintrc.json`       | `.oxlintrc.json`           | Oxlint + effect plugin; role/platform authoritative |
| `.oxfmtrc.json`        | `.oxfmtrc.json`            | Ox formatter pair                                  |
| `AGENTS.md`            | `AGENTS.md`                | Stub; PROJECT-SPECIFIC section is the only edit zone |
| `STATE.md`             | `STATE.md`                 | Mission-state skeleton                             |
| `justfile.fragment`    | merged into `Justfile`     | `check` + `conventions-check` targets              |
| `flake.nix`            | `flake.nix`                | Reference direnv shell — trim to the toolchain     |
| `.envrc`               | `.envrc`                   | `use flake`                                        |
| `.conventions-exceptions` | `.conventions-exceptions` | Declared divergences                              |

Adoption: copy the required artifacts from this directory, preserve their
stamps, and fill only the documented project-specific fields. Reef does not
materialize this profile.
Checking: `../bin/conventions-check <repo>` or `--all <root>`.

Stamped files promise byte-parity with this profile. Remove the stamp only by
declaring the divergence in `.conventions-exceptions`. Unstamped files are
hand-owned (e.g. a project's real flake.nix) and are not diffed.

Exception keys declare deliberate divergence. In a `package.json` repository,
missing `.oxlintrc.json` or `.oxfmtrc.json` is drift unless the repository
declares `key: linter`.
