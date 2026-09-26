---
name: effect-review-exceptions
description: Reviews Effect code and upgrades with the shared FX rule IDs, and owns the exception lifecycle for suppressions and non-native substitutes (record, verify, reopen on upgrade, retire). Use when reviewing Effect changes, adding a lint suppression or non-Effect substitute, or upgrading Effect or its companion packages.
---

# Effect review and exceptions

A review ranks findings by semantic risk and names each by its FX rule. An
exception is a recorded, verified, owned, and expiring decision to leave the
native path. Without the record, "Effect-first with exceptions" turns into a
permanent pile of workarounds nobody can remove.

## Look up first

- The FX registry and the enforcement vocabulary: [references/rules.md](references/rules.md).
- `node_modules/effect/AGENTS.md` and `node_modules/effect/ai-docs/src/` for the
  construct a finding says is missing; `node_modules/effect/src/` when behaviour
  is in question.
- The repository's `effect-house` overlay: its lint configuration, which
  `effecttsgo/*` diagnostics are on, its project rules, the exception registry
  path (convention: `docs/effect-exceptions.json`), and the check that validates
  it.
- For upgrades: the installed package changelogs and the upstream migration
  guide the official `effect-ts` skill names.

## Decide

**Review order.** Establish the versions and the profile (application,
integration adapter, library, migration). Then inspect, in this order: boundary
validation, error semantics, ownership and cancellation, concurrency and
capacity, durability, and only then local style. A shorter pipe chain never
outranks a correctness finding.

**A finding** records: rule ID and slug, severity, file and line, the evidence,
the semantic consequence, the smallest repair, and the test that would prove
the repair. Mark automatic fixes apart from suggestions. When the evidence
cannot establish the problem, abstain and say what evidence is missing
(`FX013`). Never report a check as passing unless it ran.

**Is an exception legitimate?** Only when the native path cannot meet a
concrete requirement after the native constructs were examined against the
installed version. Familiarity with another library, a failed search, and an
unmeasured performance worry are not reasons.

**The record** (one per decision, in the registry the overlay names):

- `id`: `EX-NNNN`.
- `rules`: FX IDs plus the tool rule names it suppresses.
- `scope`: `{ files, symbols }`; every file lies under `owner`.
- `reason`: the requirement the native path fails.
- `missingCapability`: what exactly the installed Effect cannot do.
- `nativeAlternatives`: each construct examined and why it fell short.
- `verification`: the commands or tests that prove the substitute keeps the
  semantics (typed errors, decoding, cancellation, scope ownership).
- `owner`: the module directory (one with an `AGENTS.md`) that owns the sites.
- `examinedWith`: package → version map the decision was examined against, for
  example `effect`, `@effect/tsgo`, `typescript`.
- `retirementTrigger`: the observable event that removes the exception.

A suppression names its record: `// oxlint-disable-next-line <rule> -- EX-NNNN: <reason>`.
An Effect language-service expectation tag in JSDoc carries the ID in the same
comment block.

**Lifecycle.** Open → verified → reopened when a package in `examinedWith` moves
(re-examine against the new version) → retired when the native capability
arrives. Retire by running the original regression tests against the native
path, deleting the workaround with its layers and requirements, and deleting
the record. The DXOS removal of its custom SQL transaction service after the
native Durable Object support landed (rc.115, configured with the storage
handle) is the model.

**Upgrades.** Move the whole Effect cohort together, re-apply or drop patches,
regenerate protocol artifacts, test persisted and wire compatibility, rerun
cancellation and resource tests, and reopen every exception whose
`examinedWith` names a package that moved.

## Rules

| Rule | Requirement | Enforcement |
|---|---|---|
| FX001 version-authority | Reviews and exception records cite the installed versions they were checked against; an upgrade moves the whole cohort. | `effecttsgo/duplicate-package`, `effecttsgo/outdated-api` |
| FX002 native-first | A finding that proposes a substitute names the native constructs examined; the default repair is the native construct. | review-only |
| FX012 native-workaround-retirement | Every suppression and substitute names a registered exception with all record fields; an upgrade of a package in `examinedWith` reopens it. | review-only; test: the repository's exception check named in `effect-house` fails on an unregistered suppression |
| FX013 proof-before-autofix | Apply an automatic rewrite only when binding, evaluation order, laziness, effects, and control flow provably stay the same; otherwise report and abstain. | review-only |
| FX016 lawful-performance-exception | A performance bypass needs a measured unmet requirement, exhausted native options, equivalence tests against the native path, and an approved record. | test: generated-value equivalence and mutation tests against the native codec or path |

## Verify

- Every finding has a location, evidence, and a proposed test; every "passes"
  claim names the command that ran.
- The exception registry validates with the repository's check; each record's
  `verification` commands run green at the recorded versions.
- After an upgrade, the reopened records were re-examined and either re-verified
  with the new `examinedWith` or retired.

## Escape hatches

This skill is the escape hatch for the other skills. An exception that lacks a
field, an owner, or a retirement trigger is not approved; treat the code as a
finding under `FX002` or `FX012`.

## Done means

- Findings are ordered by semantic risk and each cites an FX rule.
- No suppression or substitute in the change lacks a complete record.
- Retired exceptions are gone from both the code and the registry.
