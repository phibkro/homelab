---
name: effect-domain-constructs
description: Decides when a new Effect v4 abstraction earns its place (operation, service, combinator, or description plus interpreter), states its semantic contract, and proves its laws without inventing a competing runtime. Use when creating a reusable combinator, domain service, DSL, job or command type, or library API on top of Effect.
---

# Effect domain constructs

This skill decides how far up the abstraction ladder a piece of domain
behaviour should go, and what the resulting construct must promise. It prevents
home-made runtimes, schedulers, DI containers, and retry engines, wrappers that
hide channels or ownership, and constructs that do work when they are built.

## Look up first

- `node_modules/effect/AGENTS.md` sections: "Writing `Effect` code" (`Effect.gen`
  inline, `Effect.fn` versus `Effect.fnUntraced` for reusable functions, no
  functions that only wrap `Effect.gen`), "Batching external requests",
  "Managing resources and `Scope`s".
- `node_modules/effect/ai-docs/src/01_effect/01_basics/` — `Effect.fn`,
  `Effect.fnUntraced`, `Effect.fn.Return`, constructors from common sources.
- `node_modules/effect/ai-docs/src/05_batching/` — `Request.Class` and
  `RequestResolver`: a native description (request) plus interpreter (resolver).
- `node_modules/effect/ai-docs/src/01_effect/05_resources/` — scoped acquisition
  in services, `Layer.effectDiscard`, `LayerMap.Service` for keyed resources.
- Source for library work: `node_modules/effect/src/Function.ts` (`dual` for
  data-first and data-last forms), `src/Effectable.ts` (custom Effect-compatible
  values), `src/ExecutionPlan.ts` (a native plan of fallback steps).
- The worked design protocol: [references/design-protocol.md](references/design-protocol.md).

Stop searching when every API you will use has matching installed guidance, or
the search established that none exists (then say so in your report).

## Decide

Take the lowest rung that states the invariant you need. Each step up must name
an invariant the rung below cannot state.

1. **Pure function or schema** for data semantics (FX014). Normalization,
   aggregation, and checks on decoded values stay plain (`effect-domain-models`).
2. **Effect-returning operation** for work. Inline code is `Effect.gen`; a
   reusable function is `Effect.fn("name")` at a traced boundary or
   `Effect.fnUntraced` on a hot or library path. Never write a function that
   only wraps and returns `Effect.gen`.
3. **Service** for an external capability or an owned resource
   (`effect-services-layers`), not for every function.
4. **Combinator** when a repeated policy should compose across operations
   (bounded traversal, progress, domain retry policy). It takes an Effect and
   returns an Effect, keeps success, error, and requirement channels unless it
   deliberately maps, handles, or provides one, and offers data-first and
   data-last forms (`Function.dual`) so it works in `pipe`.
5. **Description plus interpreter** only when inspection, preview or planning,
   persistence and replay, or several interpreters (live, test, dry run) need
   it. Check the native ones first: `Request` with `RequestResolver`,
   `ExecutionPlan`, `Schedule`. A persisted plan stores data and protocol state,
   never closures or Effect values.
6. **Custom Effect-compatible datatypes** (`Effectable`, yieldable classes) and
   runtime internals are library work under the library profile (FX008). An
   application does not start there.

Before extracting anything, write the direct native composition. If it is
small and clear, keep it. Evidence for the ladder: Foldkit's Command wraps an
Effect with a name while its channels stay visible and its constructor stays
suspended; Alchemy's Provider maps resource lifecycles onto Context services, and
its casts and custom yieldability stay library-internal.

**State the semantic contract** in the construct's documentation: success type,
expected errors, requirements; who decodes input; who owns each resource; when
execution starts; what interruption does; retry and idempotency; whether state
is transient or durable. Check `effect-house` for constructs the repository
already has.

## Rules

| Rule | Requirement | Enforcement |
|---|---|---|
| FX002 native-first | A new construct sits on the lowest rung that states its invariant, after a direct native composition was written and a native construct was ruled out. | review-only; test: the construct and the direct composition agree on output, failures, requirements, and cancellation |
| FX007 lazy-construction | Building or discarding the construct does no work and cannot throw; a needed suspension stays inside the value rather than in a zero-argument thunk. | `effecttsgo/lazy-effect`; test: construct and discard with a side-effect spy and a throwing setup, and neither runs |
| FX008 capability-preservation | Combinators keep success, error, and requirement channels unless they deliberately map, handle, or provide one; no cast narrows them. | `effecttsgo/unsafe-effect-type-assertion`; test: type tests show a missing service is a compile error and an unhandled error stays in the error type |
| FX008 capability-preservation | Exported combinators offer a pipeable form; custom Effect-compatible datatypes and runtime internals appear only in library code with law tests. | `effecttsgo/missing-pipeable-signature`; review-only for `Effectable` use |
| FX011 intentional-observability | Reusable effectful functions use `Effect.fn` at meaningful boundaries and `Effect.fnUntraced` on hot or library paths; no wrapper that only returns `Effect.gen`, no `Effect.fn` called immediately. | `effecttsgo/effect-fn-opportunity`, `effecttsgo/effect-fn-iife`, `effecttsgo/unnecessary-effect-gen` |
| FX006 owned-lifetime | The construct names the owner of every resource it touches; what it acquires is released on success, failure, and interruption. | test: interrupting the construct mid-run releases each acquired resource exactly once |
| FX009 explicit-order-capacity | A construct that runs work concurrently states its bound, ordering, and admission, including callers waiting outside a queue. | test: with more tasks than the bound, active plus waiting work never exceeds the stated limit |
| FX010 persistence-semantics | The contract says whether state is transient or durable; a replayable description persists data and protocol state, and retried steps declare idempotency. | test: replaying a persisted description after a simulated crash yields the same committed result |
| FX014 pure-domain-core | No service, error channel, or Effect wrapper is added to a total deterministic function to make it look like a construct. | review-only |

## Verify

Prove the laws the contract claims; [references/design-protocol.md](references/design-protocol.md)
walks through them for a worked domain.

- Construction: build and discard; no spy fires, no setup throws.
- Channels: type tests pin success, error, and requirement types before and
  after the combinator; a missing requirement fails to compile.
- Ownership and cancellation: interrupt mid-run; finalizers run once; no late
  result or state change arrives after interruption.
- Admission: load beyond the bound; active plus waiting work stays within it.
- Durability: crash between commit and publication; replay does not duplicate
  committed effects beyond the declared idempotency.
- Equivalence: the construct agrees with the direct composition on output,
  failures, requirements, resource use, and cancellation.
- Substitution: a test layer replaces each capability without changing domain
  code; the construct creates no global runtime or fixed backend.
- The Rules diagnostics are clean; harness details: `effect-testing`.

## Escape hatches

A construct that replaces a native facility (its own scheduler, queue, retry
engine, or service locator) needs a registered exception per
`effect-review-exceptions`: scope, missing capability, native alternatives
examined, verification, owner, examinedWith versions, retirement trigger. A
suspension that looks redundant is not an exception; removing it changes when
work happens (FX007, FX013). Not a justification: "it reads like a framework",
future extensibility, familiarity with another runtime, or not finding the
native construct.

## Done means

- The direct native composition was written first; the construct names the
  invariant it adds.
- Its contract states channels, decoding owner, resource owner, start of
  execution, interruption, retry, and durability.
- Law tests cover construction, channels, ownership, cancellation, and
  equivalence, plus admission and durability where claimed; type tests pin the
  channels.
- No home-made runtime, scheduler, or locator; the Rules diagnostics are clean.
