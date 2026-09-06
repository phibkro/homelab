---
name: on-structural-change
description: Keep imports, generators, checks and current documentation coherent when moving homelab code or changing ownership.
---

Read `docs/README.md` for document ownership and
`docs/reference/module-authoring.md` for implementation ownership.

Preserve dirty operator work. Change canonical declarations first, then update
consumers and regenerate projections. Directory moves must repair Nix imports,
Just fragments, deployment source roots, tests, agent instruction sources and
current documentation. Inventory remains the host enumeration authority.

Keep historical plans and incident evidence under `docs/archive/`; current
runbooks must describe the deployed backend. Link to canonical facts instead
of maintaining another host/service list in a skill.

For mechanical moves, compare evaluated inventory before and after. Run
`just check-migration`, relevant backend checks, and generated-document freshness.
Report source checks separately from build, VM and production observations.
