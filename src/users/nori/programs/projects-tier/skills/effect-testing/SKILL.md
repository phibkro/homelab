---
name: effect-testing
description: Decides what evidence proves Effect code and how to produce it. Type tests for channels, @effect/vitest runtime tests with test layers and TestClock, synchronization on events instead of sleeps, interruption and cleanup tests, mutation checks, and intentional spans and logs. Use when writing or reviewing tests or instrumentation for Effect code, or when reporting verification.
---

# Effect testing and observability

This skill decides which evidence proves an Effect change and how to produce
it: type tests for channel contracts, runtime tests for behaviour, and spans and
logs that show what ran. It prevents tests that pass by sleeping, by never
running the Effect, or by restating the implementation, and reports that claim
checks nobody ran.

## Look up first

- `node_modules/effect/AGENTS.md` sections: "Testing Effect programs",
  "Observability", "Writing `Effect` code", "Writing Effect services",
  "Working with DateTime".
- `node_modules/effect/ai-docs/src/09_testing/`: `10_effect-tests.ts`
  (`it.effect`, `it.effect.each`, `it.live`, `TestClock.adjust`,
  `it.effect.prop` with Schema inputs) and `20_layer-tests.ts` (shared
  `layer(...)` suites, test layers composed with `Layer.provideMerge`).
- `node_modules/effect/ai-docs/src/51_http-server/20_testing.ts`:
  `HttpApiTest.groups`, `HttpServer.layerServices`, `Effect.flip`.
- `node_modules/effect/ai-docs/src/08_observability/`: `Logger.layer`,
  `References.MinimumLogLevel`, `Effect.annotateLogs`, `Effect.withLogSpan`,
  `Effect.withSpan`, `Effect.annotateSpans`, `Layer.withSpan`, the Otlp layers.
- Installed source for exact behaviour: `@effect/vitest` `src/index.ts` (test
  variants, `layer` options, `flakyTest`); `effect/src/testing/` (`TestClock`,
  `TestConsole`, `TestSchema`); `effect/src/Deferred.ts`, `Latch.ts`,
  `Queue.ts`, `Fiber.ts`.
- `effect-house` for the test command, the type-test tool, and the lint
  configuration of the repository.

Stop searching when every API you will use has matching installed guidance or
source, or the search established that none exists (then say so in your
report).

## Decide

1. **Type or runtime evidence?** A type test proves channel shapes: the
   success, error, and requirement types a construct infers, keeps, or
   eliminates. It proves nothing about release, cancellation, retry, replay, or
   wire compatibility. Write type tests where channels are the contract of a
   construct you publish; write runtime tests for everything it does.
2. **Which runner?** Default to `it.effect`: each test gets a Scope and the test
   services (`TestClock`, `TestConsole`). Use `it.live` only when the test needs
   the real clock or console. Tables use `it.effect.each`; laws and codec round
   trips use `it.effect.prop` or `it.prop` with Schema inputs, and
   `TestSchema.Asserts` covers decoding, encoding, and lossless round trips.
   Assert with the `assert` export of `@effect/vitest`. A plain Vitest callback
   that returns an Effect never runs it.
3. **Which dependencies?** Build test layers from the production service
   interface (`effect-services-layers`): an in-memory implementation whose
   dependencies are composed with `Layer.provideMerge`, so the test can read the
   test state. `layer(...)` shares one layer across a block and releases it
   after the block, so state carries between its tests; provide per test when
   isolation matters. Never swap a service by casting or by mocking imports.
4. **How does time pass?** Under `it.effect` the clock stands still: fork the
   effect, move time with `TestClock.adjust` or `TestClock.setTime`, then
   observe. Code that reads `Date.now` or waits with `setTimeout` escapes the
   test clock; it must use `Clock`, `DateTime`, `Effect.sleep`, or `Schedule`.
5. **What signals completion?** An event the code under test produces: a
   `Deferred` or `Latch` it completes, a receipt, a `Queue` drained to the
   expected size, `Fiber.await` or `Fiber.join`. A timeout may bound a stuck
   test; it never signals success. Wait for the milestone the claim is about:
   accepted, committed, projected, or externally completed (T3 Code tests wait
   on receipts and worker drains, not sleeps).
6. **Does cleanup hold?** For each resource: fork its user, wait for acquisition
   on a `Deferred`, interrupt, and assert the finalizer receipt and an
   interrupted Exit. Repeat on success and failure; a Stream also needs early
   termination by its consumer. When a foreign host can end the process or page,
   test release through that boundary (OpenCode's spinner called process exit
   and skipped finalizers).
7. **HTTP handlers?** Test through `HttpApiTest.groups` with in-memory service
   layers and `HttpServer.layerServices`: real encoding, routing, and decoding
   without a socket. Assert typed errors through `Effect.flip` and vary the
   client middleware per case.
8. **Does the test detect the bug?** Name the plausible bug each test fails on.
   Break the defended behaviour once (drop the finalizer, the suspension, or the
   narrow catch), watch the test fail, restore. A test that still passes is not
   evidence. Never re-implement the code under test inside the assertion.
9. **What should be observable?** Give meaningful boundaries (service methods,
   handlers, jobs) a span through `Effect.fn` with a name that matches the
   function. Keep hot helpers and library internals on `Effect.fnUntraced`. Log
   through `Effect.log*` with `Effect.annotateLogs` context, never the console.
   Carry secrets as `Redacted` (`Config.Redacted`) and keep them out of
   messages, annotations, and span attributes. Configure loggers and exporters
   once at the entry point; capture log output in a test with `TestConsole`.

Recipes and a review checklist:
[references/test-recipes.md](references/test-recipes.md).

## Rules

| Rule | Requirement | Enforcement |
|---|---|---|
| FX015 observable-tests | Tests wait on events the code produces (`Deferred`, `Latch`, receipt, queue drain, `Fiber.await`) and move time with `TestClock`; no sleep or timeout signals success, and each test fails when the defended behaviour is removed. | `effecttsgo/floating-effect-in-vitest`, `effecttsgo/global-timers`, `effecttsgo/global-timers-in-effect`, `effecttsgo/global-date`; test: a one-line mutation of the defended code makes the test fail |
| FX006 owned-lifetime | Every resource and fiber a test starts is released by the test Scope or its `layer` block, and each resource has an interruption test. | test: interrupt after acquisition, then observe the finalizer receipt and an interrupted Exit |
| FX005 honest-error-channel | Assert each expected failure through the error channel (`Effect.flip`, `Effect.exit`) and keep failure, defect, and interruption apart; no test catches everything to pass. | test: one case per expected failure tag plus a defect or interruption case; review-only |
| FX008 capability-preservation | A construct whose channels are its contract has type tests for its inferred success, error, and requirement types, plus a negative case that fails when a requirement is erased or an error widened. | `effecttsgo/unsafe-effect-type-assertion`; test: type tests with Vitest `expectTypeOf` or the repository's type-test runner |
| FX007 lazy-construction | A builder that promises laziness (command, layer, Effect-returning function) has a construct-and-discard test. | test: construct and discard, then observe zero calls on a probe |
| FX011 intentional-observability | Spans mark meaningful boundaries through `Effect.fn`; hot and library helpers use `Effect.fnUntraced`; logs go through `Effect.log*` with annotations and carry no secrets. | `effecttsgo/effect-fn-opportunity`, `effecttsgo/global-console`, `effecttsgo/global-console-in-effect`; review-only for span placement and redaction |
| FX013 proof-before-autofix | Accept a lint fix, codemod, or simplification only after tests that pin evaluation order, laziness, and effects pass before and after it. | test: the same behaviour suite passes before and after the rewrite; review-only |
| FX016 lawful-performance-exception | A performance bypass ships with a measurement of the unmet requirement and a property test that compares it with the native path over generated inputs. | test: property test of bypass versus native output; review-only |
| FX001 version-authority | Test with the `@effect/vitest` release whose `effect` peer range matches the installed `effect`; the program holds one copy of each Effect package. | `effecttsgo/duplicate-package` |

`effecttsgo/effect-fn-opportunity` marks a function that returns an Effect
without `Effect.fn`; choose `Effect.fn` or `Effect.fnUntraced` by whether the
boundary deserves a span.

## Verify

- Run the repository's test command and its type check with Effect diagnostics
  (`effect-house` or `AGENTS.md` name them). Record exact commands and results.
- Each new or changed test names its plausible bug, and the mutation that made
  it fail was run once.
- Resources have interruption and cleanup tests; time moves through
  `TestClock`; no test waits for success on a sleep, a timeout, or a frame.
- Type tests exist where channels are the contract, including a negative case.
- The diagnostics in the Rules table are clean on touched files, or each finding
  names a registered exception.
- Spans and logs were read once in a real run or a `TestConsole` capture: names
  match functions, context is present, no secret appears.

## Escape hatches

`it.live` and real I/O are legitimate in an integration test about that
integration; say why the test needs them. `flakyTest` retries an Effect within a
time budget; use it only for an external dependency you cannot control, never to
hide a race in your own code. A real-time wait, a retried flaky test, or a
mocked module needs a registered exception (`effect-review-exceptions`) naming
`EX-NNNN`, rules, scope, reason, missingCapability, nativeAlternatives (the test
services, test layers, `Deferred`, `Latch`), verification, owner, examinedWith
(`effect` and `@effect/vitest` versions), and retirementTrigger. Not a
justification: "the test was flaky", "it passed locally", familiarity, or
"could not find the API".

## Done means

- Every changed behaviour has a runtime test that fails when the behaviour is
  removed; channel contracts have type tests.
- Resources have interruption and cleanup tests; tests synchronize on events
  and control time with `TestClock`.
- Meaningful boundaries carry spans, hot helpers stay untraced, and logs are
  structured and secret-free.
- Rules-table diagnostics are clean or name a registered exception.
- The report lists the exact commands run with their results and every check not
  run. Planned, author-reported, or unexecuted tests are never reported as
  passed.
