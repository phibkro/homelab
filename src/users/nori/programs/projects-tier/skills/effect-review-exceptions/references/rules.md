# FX rule registry and enforcement vocabulary

The shared vocabulary for tier skills, review findings, and exception records.
The IDs and slugs come from the operator's research pack
(`effect-v4-skill-research-pack-2026-09-26`, `rules.json`, a draft registry that
is not a linter). The requirement text is rewritten for the tier. A skill's
`## Rules` table cites rules as `FXnnn slug`; the homelab eval check rejects an
ID or slug that is not in the table below.

## Registry

| ID | Slug | Applies to | Requirement |
|---|---|---|---|
| FX001 | version-authority | all | Establish the installed Effect version, companion packages, overrides, and patches before choosing an API. A "v4" label is not a version. |
| FX002 | native-first | application | Use the native construct, then a composition of native constructs, then a small domain abstraction built from them. A substitute needs an evidenced capability gap. |
| FX003 | owned-runtime-boundary | application | Run effects only at owned entry points (process main, framework handler, FFI callback). Domain code never runs a runtime to get back to a Promise. |
| FX004 | typed-boundary | all | Decode untrusted data once, with a schema, at the boundary that owns it. A type argument, cast, or `JSON.parse` result is not a parsed value. |
| FX005 | honest-error-channel | all | Expected failures stay typed in the error channel. Defects, interruption, and unrelated I/O failures never collapse into a success fallback. |
| FX006 | owned-lifetime | all | Every scope, resource, fiber, and subscription has one named owner that releases it on success, failure, and interruption. |
| FX007 | lazy-construction | all | Building or discarding a computation, command, or layer performs no work. Keep a suspension when constructor purity depends on it. |
| FX008 | capability-preservation | library | Combinators keep the success, error, and requirement channels unless they deliberately transform, handle, or provide one. No cast erases a requirement. |
| FX009 | explicit-order-capacity | all | State ordering, capacity, admission, backpressure, and cancellation. A concurrent batch implies none of them. |
| FX010 | persistence-semantics | application | Local fibers, queues, and locks give no durable or cross-process guarantee. State commit, acknowledgement, idempotency, and retry semantics. |
| FX011 | intentional-observability | all | Trace meaningful boundaries, keep hot leaf helpers untraced, and keep failure context without leaking secrets. |
| FX012 | native-workaround-retirement | all | Record every fallback as an exception with scope, examined versions, capability gap, verification, owner, and retirement trigger. Revisit it on a matching upgrade. |
| FX013 | proof-before-autofix | tooling | Rewrite code automatically only when binding, evaluation order, laziness, effects, and control flow provably stay the same. Otherwise report and abstain. |
| FX014 | pure-domain-core | application | Total deterministic transformations stay plain functions. Do not add services, error channels, or effect wrappers for uniformity. |
| FX015 | observable-tests | all | Tests observe completion, interruption, cleanup, and laws, synchronizing on events rather than sleeps or duplicated implementation. |
| FX016 | lawful-performance-exception | all | A performance bypass of a native path needs a measured unmet requirement, exhausted native options, preserved semantics, and an approved exception. |

## Enforcement vocabulary

Each rule row's `Enforcement` cell uses one or more of these forms:

- `` `effecttsgo/<rule>` `` names a diagnostic of the Effect language service
  (`@effect/tsgo`), reported through `tsc`, `effect-tsgo diagnostics`, or the
  Oxlint patch. It exists in the package; whether it is on, and at what
  severity, is repository configuration that the `effect-house` overlay
  records.
- `test: <what the test observes>` names the evidence a test must produce.
- `review-only` states that no tool detects the rule; a reviewer checks it.

Rule names below come from `@effect/tsgo` 0.36.4 (`oxlint-presets/*.json` and
the README diagnostics table). The eval check accepts only these names; when a
project upgrades `@effect/tsgo`, re-read its README and update this list.

- Correctness: `effecttsgo/any-unknown-in-error-context`,
  `effecttsgo/class-self-mismatch`, `effecttsgo/duplicate-package`,
  `effecttsgo/effect-fn-implicit-any`, `effecttsgo/floating-effect`,
  `effecttsgo/floating-effect-in-vitest`, `effecttsgo/generic-effect-services`,
  `effecttsgo/missing-effect-context`, `effecttsgo/missing-effect-error`,
  `effecttsgo/missing-layer-context`, `effecttsgo/missing-return-yield-star`,
  `effecttsgo/missing-star-in-yield-effect-gen`,
  `effecttsgo/non-object-effect-service-type`, `effecttsgo/outdated-api`,
  `effecttsgo/overridden-schema-constructor`,
  `effecttsgo/promise-in-effect-success`,
  `effecttsgo/schema-literal-non-finite`,
  `effecttsgo/schema-opaque-instance-member`.
- Anti-pattern: `effecttsgo/catch-unfailable-effect`,
  `effecttsgo/effect-fn-iife`, `effecttsgo/effect-gen-uses-adapter`,
  `effecttsgo/effect-in-failure`, `effecttsgo/effect-in-void-success`,
  `effecttsgo/global-error-in-effect-catch`,
  `effecttsgo/global-error-in-effect-failure`,
  `effecttsgo/layer-merge-all-with-dependencies`, `effecttsgo/lazy-effect`,
  `effecttsgo/lazy-promise-in-effect-sync`, `effecttsgo/leaking-requirements`,
  `effecttsgo/multiple-effect-provide`, `effecttsgo/prefer-unsafe-constructor`,
  `effecttsgo/return-effect-in-gen`, `effecttsgo/run-effect-inside-effect`,
  `effecttsgo/schema-sync-in-effect`, `effecttsgo/scope-in-layer-effect`,
  `effecttsgo/strict-effect-provide`, `effecttsgo/try-catch-in-effect-gen`,
  `effecttsgo/unknown-in-effect-catch`.
- Effect-native: `effecttsgo/abort-controller-in-effect`,
  `effecttsgo/async-function`, `effecttsgo/crypto-random-uuid`,
  `effecttsgo/crypto-random-uuid-in-effect`, `effecttsgo/extends-native-error`,
  `effecttsgo/global-console`, `effecttsgo/global-console-in-effect`,
  `effecttsgo/global-date`, `effecttsgo/global-date-in-effect`,
  `effecttsgo/global-fetch`, `effecttsgo/global-fetch-in-effect`,
  `effecttsgo/global-random`, `effecttsgo/global-random-in-effect`,
  `effecttsgo/global-timers`, `effecttsgo/global-timers-in-effect`,
  `effecttsgo/instance-of-schema`, `effecttsgo/new-promise`,
  `effecttsgo/node-builtin-import`, `effecttsgo/prefer-schema-over-json`,
  `effecttsgo/process-env`, `effecttsgo/process-env-in-effect`,
  `effecttsgo/unsafe-effect-type-assertion`.
- Style: `effecttsgo/catch-all-to-map-error`,
  `effecttsgo/catch-chain-to-first-success-of`,
  `effecttsgo/catch-tag-to-catch-reason`, `effecttsgo/catch-to-ignore`,
  `effecttsgo/catch-to-or-else-succeed`, `effecttsgo/deterministic-keys`,
  `effecttsgo/effect-do-notation`, `effecttsgo/effect-fn-opportunity`,
  `effecttsgo/effect-map-flatten`, `effecttsgo/effect-map-void`,
  `effecttsgo/effect-succeed-with-void`, `effecttsgo/flat-map-to-map`,
  `effecttsgo/missed-pipeable-opportunity`,
  `effecttsgo/missing-effect-service-dependency`,
  `effecttsgo/missing-pipeable-signature`, `effecttsgo/multiple-catch-tag`,
  `effecttsgo/nested-effect-gen-yield`, `effecttsgo/new-schema-class`,
  `effecttsgo/prefer-schema-type-property`,
  `effecttsgo/prefer-typed-schema-decoder`, `effecttsgo/redundant-map-error`,
  `effecttsgo/redundant-or-die`, `effecttsgo/redundant-schema-tag-identifier`,
  `effecttsgo/schema-number`, `effecttsgo/schema-struct-with-tag`,
  `effecttsgo/schema-union-of-literals`, `effecttsgo/service-not-as-class`,
  `effecttsgo/strict-boolean-expressions`, `effecttsgo/sync-to-succeed`,
  `effecttsgo/unnecessary-arrow-block`, `effecttsgo/unnecessary-effect-gen`,
  `effecttsgo/unnecessary-fail-yieldable-error`, `effecttsgo/unnecessary-pipe`,
  `effecttsgo/unnecessary-pipe-chain`, `effecttsgo/unnecessary-typeof-type`.

Project rules (for example Oxlint plugins a repository vendors) and repository
checks such as an exception-registry check belong in the repository's
`effect-house` overlay, which maps them to these FX IDs.
