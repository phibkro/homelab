<!-- generated-by: foundry@v1 -->
# AGENTS.md — project contract

Generated boilerplate from `homelab/foundry/profile-v1` (single source:
homelab/docs/PROJECTS.md, "Project conventions contract"). Hand edits here are
flagged as drift by `conventions-check`; record real divergences in
`.conventions-exceptions` instead.

## Contract

- **Mission state:** `STATE.md` is the single mission-state file. It declares a
  lifecycle — `idea | spec | spec-frozen | build | park | archive` — plus
  Now / Next / Blocked. Agents read it first; keep it current.
- **Agent doc:** this file is THE agent doc. Where a harness wants CLAUDE.md,
  it is a symlink to AGENTS.md. Never a second prose copy.
- **Specs:** design work lives in `design-specs/`. Lifecycle ≥ spec requires
  that directory to exist.
- **Lifecycle gates:** idea → spec → spec-frozen → build → park → archive, one
  executable gate per transition (defined in the conventions contract).
  spec-frozen additionally requires `Frozen: yes` in STATE.md.
- **Checks:** `just check` = lint + format (+ typecheck/tests per toolchain);
  `just conventions-check` = conventions drift gate. Both green before merge.

## PROJECT-SPECIFIC (replace this section)

<!-- Everything above is generated boilerplate — regenerate, don't edit.
     Replace the placeholder below with this project's own instructions. -->

- Runtime / package manager:
- Build, typecheck, test entry points:
- What an agent must know that is unique to this repo:
