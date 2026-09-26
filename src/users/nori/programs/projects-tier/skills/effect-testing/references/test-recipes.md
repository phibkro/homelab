# Test recipes and review checklist

Each recipe says what the test observes and which plausible bug it fails on.
Look up every named API in the installed guidance first: `@effect/vitest`
`src/index.ts`, `node_modules/effect/ai-docs/src/09_testing/`, and
`effect/src/testing/`.

## Time-dependent behaviour

1. Fork the effect under test inside `it.effect`.
2. Move time with `TestClock.adjust` (or `TestClock.setTime`) to just before the
   deadline and observe that nothing happened; move past it and observe the
   outcome (`Fiber.await` or `Fiber.join`).
3. `TestClock` logs a warning when a test uses time without advancing the clock;
   treat that warning as a hanging test.

Fails on: a retry, timeout, or schedule that fires early, late, or never.

## Interruption and cleanup

1. Give the release or finalizer a receipt: a `Deferred` it completes.
2. Fork the user of the resource; wait on an acquisition `Deferred`.
3. Interrupt the fiber with `Fiber.interrupt`; await the release receipt and
   check that the fiber's Exit is an interruption.
4. Repeat with the use succeeding and failing.

Fails on: a resource built before its acquire step, a missing finalizer, a
detached fork that survives the scope.

## Queue and worker drains

Offer the work, then wait on the observable milestone: the receipt the worker
produces, or the queue drained to the expected size. Assert the milestone the
claim is about (accepted, committed, projected, externally completed).

Fails on: work reported complete before it was committed.

## Test layers

Implement the production service interface in memory. Compose its dependencies
with `Layer.provideMerge` so the test can read test state (a Ref service, as in
`ai-docs/src/09_testing/20_layer-tests.ts`). Choose shared `layer(...)` blocks
for expensive layers whose state may carry between tests, and per-test
provision when each test needs a fresh state.

Fails on: a test double that diverges from the interface, hidden shared state.

## HttpApi handlers

Build the client with `HttpApiTest.groups` over the handler layer, in-memory
services, and `HttpServer.layerServices`. Cover the success path, each typed
error through `Effect.flip`, and each client middleware variant (valid,
missing, and wrong credentials).

Fails on: schema drift between handler and client, a middleware that lets an
unauthenticated request through.

## Laws and codecs

Use `it.effect.prop` or `it.prop` with Schema inputs for laws (round trip,
idempotence, associativity of a combinator). Use `TestSchema.Asserts` for
decoding, encoding, and lossless round trips of a Schema.

Fails on: a codec that loses information, a combinator that breaks a law on an
edge case.

## Type tests

For a construct whose channels are its contract, assert the inferred success,
error, and requirement types. Add a negative case marked as an expected type
error: a call that omits a required service, or a mapping that would widen the
error. Use Vitest `expectTypeOf` (re-exported by `@effect/vitest`) or the
runner `effect-house` names.

Fails on: a cast that erases a requirement, an overload that widens the error
channel.

## Mutation check

For each new test, change the defended code once (delete the finalizer, remove
the suspension, widen the catch, swap two steps), run the test, see it fail,
and restore. Record the mutation in the report.

## Review checklist

- Does any test pass without running its Effect (a plain callback returning an
  Effect)?
- Does any test wait for success on a sleep, a timeout, or a frame?
- Does any code under test read `Date.now` or use `setTimeout` so that the test
  clock cannot reach it?
- Does every resource have an interruption test?
- Does every expected failure have a test through the error channel?
- Are spans on meaningful boundaries only, and are secrets absent from logs and
  span attributes?
- Does the report list commands actually run, with results, and name the checks
  that did not run?
