---
name: effect-first
description: Router for Effect v4 TypeScript work. Sets the lookup order (repository overlay, installed Effect guidance, house constructs, then composition), establishes versions, applies the native-first decision ladder, and routes to the specialist tier skills. Use when writing, changing, or reviewing TypeScript in a repository that depends on effect.
---

# Effect first

Every TypeScript change in an Effect repository starts here. This skill decides
which guidance applies and in which order; the specialist skills decide the
details. It prevents two failures: writing Effect from memory (API names drift
between releases, and every third-party catalogue has drifted), and reaching for
a non-Effect package before establishing that Effect cannot express the intent.

## Look up first

Work down this order and stop when the question is answered.

1. **The repository.** Identify it: the git toplevel of the files you touch.
   Read `<repo root>/AGENTS.md`. If `<repo root>/.agents/skills/effect-house/SKILL.md`
   exists, read it and the references it links before writing code, even when
   nothing loaded it for you. Task subagents receive no `AGENTS.md` as context;
   the projects-tier hook injects the chain on first touch, but read the files
   yourself when you did not see them.
2. **The versions.** Establish what is installed, not what a label says:

   ```sh
   jq -r .version node_modules/effect/package.json
   jq '{dependencies, devDependencies, overrides, patchedDependencies}' package.json
   ls node_modules/@effect
   ```

   Record the Effect version, companion packages (`@effect/*` platform,
   `@effect/vitest`, SQL drivers, `@effect/tsgo`), overrides, and patches.
3. **The installed Effect guidance.** Read `node_modules/effect/AGENTS.md`
   completely once per session (the official `effect-ts` skill asks for this),
   then the `node_modules/effect/ai-docs/src/<topic>/` examples it links for each
   API you will use, then `node_modules/effect/src/` for exact behaviour. Never use
   another copy: not GitHub main, not a blog, not memory.
4. **The house constructs.** Reuse what `effect-house` names (constructs,
   composition roots, generated docs such as `docs/constructs.md`) before
   composing something new.
5. **Compose.** Only now write the composition.

You are ready to write when every Effect API you will use has matching
installed guidance or source, or the search established that none exists. Say
which in your report.

## Decide

Take the first rung of the ladder that satisfies the requirement:

1. **Pure stays pure.** A total, deterministic transformation (arithmetic,
   mapping, formatting, checks on already-decoded data) is a plain function. It
   gets no error channel, no service, and no effect wrapper.
2. **Native construct.** Use the installed module that does exactly this job.
3. **Composition** of native constructs.
4. **Small domain abstraction** built from Effect: a service for a capability or
   owned resource, a combinator for repeated policy (`effect-domain-constructs`).
5. **Boundary adapter** for an unavoidable foreign API (`effect-boundary-adapters`).
6. **Registered exception** with a retirement trigger (`effect-review-exceptions`).
   "I could not find the API" and "I know library X better" are not capability
   gaps.

Common reaches and the native family to look up instead:

| You reach for | Look up in the installed guidance | Flagged by |
|---|---|---|
| `fetch` | `HttpClient` (`ai-docs/src/50_http-client`) | `effecttsgo/global-fetch` |
| `Date`, `Date.now` | `DateTime`, `Clock` (`07_datetime`) | `effecttsgo/global-date` |
| `setTimeout`, `setInterval` | `Effect.sleep`, `Schedule` (`06_schedule`) | `effecttsgo/global-timers` |
| `process.env` | `Config`, `Layer.unwrap` (`01_effect/03_services`) | `effecttsgo/process-env` |
| `JSON.parse`, hand-written guards | `Schema` (`01_effect/02_schema`), `Predicate` (`10_predicate`) | `effecttsgo/prefer-schema-over-json` |
| `console.*` | `Effect.log`, `Logger` (`08_observability`) | `effecttsgo/global-console` |
| `Math.random`, `crypto.randomUUID` | `Random` | `effecttsgo/global-random`, `effecttsgo/crypto-random-uuid` |
| `node:fs`, `node:path`, `node:child_process` | `FileSystem`, `Path`, `ChildProcess` (`60_child-process`) | `effecttsgo/node-builtin-import` |
| `async`/`await`, `new Promise` | `Effect.gen`, `Effect.fn` (`01_effect/01_basics`) | `effecttsgo/async-function`, `effecttsgo/new-promise` |
| `class … extends Error` | tagged errors (`01_effect/04_errors`) | `effecttsgo/extends-native-error` |

Then load the specialist skill for the work:

| Work | Skill |
|---|---|
| Schemas, IDs, commands, events, decoding | `effect-domain-models` |
| Services, layers, configuration, composition roots | `effect-services-layers` |
| Expected failures, recovery, retries | `effect-errors-recovery` |
| Scopes, fibers, queues, locks, cancellation | `effect-resources-concurrency` |
| HTTP, RPC, streams, CLIs, wire formats | `effect-streams-protocols` |
| Promise, callback, SDK, and framework boundaries | `effect-boundary-adapters` |
| SQL, transactions, durable workflows, receipts | `effect-persistence-workflows` |
| Foldkit updates, commands, subscriptions | `effect-ui-lifetimes` |
| New services, combinators, DSLs, libraries | `effect-domain-constructs` |
| Tests, laws, tracing | `effect-testing` |
| Reviews, suppressions, exceptions, upgrades | `effect-review-exceptions` |

## Rules

| Rule | Requirement | Enforcement |
|---|---|---|
| FX001 version-authority | Establish the installed Effect and companion versions, overrides, and patches before choosing an API; resolve API questions against the installed guidance and source only. | `effecttsgo/duplicate-package`, `effecttsgo/outdated-api`; review-only for the lookup itself |
| FX002 native-first | Climb the decision ladder; a non-Effect package or hand-written substitute needs the established absence of a native construct. | `effecttsgo/global-fetch`, `effecttsgo/global-date`, `effecttsgo/global-timers`, `effecttsgo/process-env`, `effecttsgo/node-builtin-import`, `effecttsgo/async-function`, `effecttsgo/new-promise` |
| FX003 owned-runtime-boundary | Run effects only at entry points: process main, framework handler, FFI callback. | `effecttsgo/run-effect-inside-effect`, `effecttsgo/floating-effect` |
| FX012 native-workaround-retirement | Every substitute or suppression names a registered exception; the repository's exception check, when `effect-house` names one, enforces it. | review-only |
| FX014 pure-domain-core | Total deterministic transformations stay plain functions. | `effecttsgo/unnecessary-effect-gen`; review-only |

## Verify

- Run the repository's type check with Effect diagnostics, lint, and tests as
  `effect-house` or `AGENTS.md` name them. Diagnostics on the files you touched
  are clean; you added no suppression without an exception ID.
- Tests prove the behaviour you changed, including its failure and interruption
  paths (`effect-testing`).
- Your report lists the Effect version, the installed guidance you consulted,
  the commands you ran with their results, and every check you did not run.

## Escape hatches

A legitimate exception names what the native path cannot do, which native
constructs were examined, how the substitute is verified, who owns it, the
versions examined, and the trigger that retires it. `effect-review-exceptions`
owns the record format and lifecycle. Performance is not an exception without
measurements (`FX016`).

## Done means

- The lookup order was followed; every Effect API used has installed guidance or
  source behind it.
- Each piece of behaviour sits on the lowest rung of the ladder that satisfies
  it; pure code stayed pure.
- Checks ran and passed, or the report names what did not run and why.
- No suppression or substitute lacks a registered exception.
