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

Generation: `reef init` overlay from this profile (new + converging repos).
Checking: `../bin/conventions-check <repo>` or `--all <root>`.

Stamped files promise byte-parity with this profile. Remove the stamp only by
declaring the divergence in `.conventions-exceptions`. Unstamped files are
hand-owned (e.g. a project's real flake.nix) and are not diffed.
