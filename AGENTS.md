# Working in this repository

Use this guide for every harness. User instructions and authorization in the
current session take precedence over repository procedures.

## Orient before editing

1. Run `git status --short` and identify the checkout and existing edits. Preserve
   operator work; isolate substantial refactors when the checkout is already dirty.
2. Read [README.md](README.md) for boundaries, then the applicable scoped guide:
   [infrastructure](src/infra/AGENTS.md), [services](src/services/AGENTS.md), or
   [users](src/users/AGENTS.md).
3. Follow [the documentation map](docs/README.md) for the current task. Historical
   plans and reports under `docs/archive/` are evidence, not current instructions.

Facts have one authoritative home:

| Question | Source |
|---|---|
| Hosts, backends, placement, endpoints, backup policy | `src/inventory/` → `nix eval --json .#lib.noriInventory` |
| Workstation realization and shared Nix modules | `src/infra/workstation/`, `src/infra/common/nixos/` |
| Pi realization and production connection contract | `src/infra/pi/`, `src/infra/common/ansible/` |
| Service manifests and concrete implementations | `src/services/` |
| User identity, home composition, and programs | `src/users/` |
| Generated documentation | `docs/generated/`; change its source and regenerate |
| Global harness instructions | `src/users/nori/programs/agent-soul/SOUL.md` and adjacent harness modules |

Do not infer a live deployment from source configuration. Verify runtime state
separately when the task depends on it.

## Edit and verify

```text
source → focused edit → fast checks → relevant build/runtime test → evidence
```

- Reuse existing inventory compilers, modules, Just recipes and procedures before
  adding another mechanism. Project procedures live in `.claude/skills/` and
  `.agents/skills/`; load only the relevant skill.
- `just` lists commands. `just check` runs fast Nix checks; `just pi::check`
  checks Ansible. `just build` builds the local NixOS configuration.
- `just check-vm [name]` runs disposable NixOS tests; `just pi::test` runs a
  disposable Pi. `just check-all` includes the full Nix check suite. Coordinate
  heavy jobs so one project lead runs at most one at a time.
- Checks report evidence, not approval. Record the tested revision and dirty
  state, commands, outcomes, and checks not run. Watch real IO/network journeys
  when changing those boundaries. See [testing guidance](docs/reference/testing-methodology.md).
- After a structural change, update affected routes/examples and run
  `just check-migration`. [Onboarding](docs/installs/agent-onboarding-test.md)
  checks whether a fresh agent can find the sources and choose verification.

## Effects and authority

Read-only inspection, reversible source edits, builds, and disposable tests can
proceed within the user's task. Do not add a confirmation gate before tool use.
Carry existing authorization forward; ask only when an effect exceeds it.

Live activation (`just activate-test`, `rebuild`, `boot`, `deploy`, `push`,
`remote …`, and `pi::deploy`) changes machines. Publishing, credentials, and
material deletion also need applicable operator authority. Prepare the diff,
builds, and evidence first when approval is still needed; see
[deployment](docs/reference/deployment.md).

- Never erase SSH trust to silence a mismatch. Verify the replacement key through
  an independently trusted channel before changing a pin or known-host entry.
- Identify disks by `/dev/disk/by-id/`, model and serial before storage changes;
  device enumeration is unstable. Formatting and deleting archives require
  explicit authorization. Follow [recovery constraints](docs/reference/recovery.md).
- Keep plaintext secrets out of code, logs, and reports. Encrypted SOPS files and
  public keys are distinct from private credentials.
- Preserve explicit access, backup and hardening intent. When changing policy,
  update its canonical declaration and verify the resulting runtime behavior.
