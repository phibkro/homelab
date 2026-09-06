---
summary: A fresh-agent exercise graded against current inventory, source and command behavior.
---

# Agent onboarding test

Use this after changing repository structure or agent instructions. Start a fresh
agent with the prompt below. Its answers must cite files and observed output;
this document deliberately contains no copied host table or expected IP address.

> Read AGENTS.md, follow its routes, and answer the questions below. Inspect only;
> do not activate, deploy, edit credentials, reset SSH trust or run heavy tests.
> Name uncertainty instead of guessing. Record the revision and dirty state.

## Questions

1. Which hosts are managed, and which backend manages each? What are their
   selected workloads? Which host receives a NixOS build target?
2. Locate Jellyfin's placement, endpoint declaration and implementation. Explain
   how changing a profile can change placement without editing the runtime.
3. Locate the current backup policy. Distinguish declared intent, enabled
   scheduling and evidence of a recoverable live backup.
4. Where would you add a workload's shared endpoint metadata, NixOS implementation
   and Pi implementation? How do you select which backend owns it?
5. How do modules reference a host's identity without copying an address? Trace
   the fact from inventory into a consumer.
6. Select checks for an inventory-only change, a Nix runtime change and a Pi role
   change. Which checks can establish real convergence or restore behavior?
7. What does bare `just` do? Which commands build, test disposable machines, or
   activate a live system? Is `activate-test` an offline preview?
8. What should happen when SSH reports a changed key, or a storage change names
   an NVMe enumeration rather than a verified disk identity?
9. Which source generates global harness instructions? Which guide owns project
   instructions? Where should a newly discovered procedural gap be repaired?
10. How do you preserve an operator's dirty work and identify the exact content
    your checks verified? What evidence is still missing before deployment?

## Grade against the source

First capture the facts from the same checkout the agent inspected:

```bash
git rev-parse HEAD
git status --short
inventory_file=$(mktemp /tmp/homelab-onboarding.XXXXXX.json)
nix eval --json .#lib.noriInventory > "$inventory_file"
just --dry-run
just --list
```

Apply this jq projection to the inventory JSON (`jq '<projection>' "$inventory_file"`):

<!-- onboarding-query:start -->
```jq
{
  hosts: (.hosts | map_values({kind, profiles, workloads})),
  jellyfin: .workloads.jellyfin,
  backup: (.backup | {enabled, targetName, targetHost, mountPoint}),
  deployment: .deployment
}
```
<!-- onboarding-query:end -->

The inventory query is also exercised by `routing-coherence` when supplied the
public inventory JSON in its Nix check. No answer key needs synchronizing when
hosts, placement or backup policy change.

| Questions | Acceptance source |
|---|---|
| 1–3 | Evaluated public inventory above; runtime modules and live evidence where claimed |
| 4–5 | `inventory/default.nix`, [module authoring](../reference/module-authoring.md), relevant manifest and generator/consumer |
| 6–7 | `Justfile`, `infra/pi/pi.just`, [testing methodology](../reference/testing-methodology.md), dry-run output |
| 8 | Root `AGENTS.md`, production SSH runner, [recovery constraints](../reference/recovery.md) |
| 9 | Root/scoped `AGENTS.md`, `users/nori/programs/agent-soul/SOUL.md`, relevant procedure |
| 10 | Observed Git state, test logs and [deployment gates](../reference/deployment.md) |

Pass each answer only if it is supported, reachable through the guides, and
separates source behavior from runtime observations. An unsupported claim of
safe activation, valid SSH identity, or working backups fails the exercise even
if other answers are correct.

Classify failures as missing knowledge, broken routing, misleading commands or
unsupported inference. Fix the canonical source or the narrowest guide and
repeat the failed questions. The shell coherence checks verify routing and query
shape; this exercise verifies whether an agent can use them effectively.
