# Lifetime test recipes

Each recipe names what it observes and the plausible bug it fails on. Look up
the step names in the installed `node_modules/foldkit/dist/test/story.d.ts`,
`test/scene.d.ts`, and `@effect/vitest`; see `effect-testing` for runners,
synchronization, and mutation checks.

## Construct and discard

1. Provide a probe service that records every call (a Ref-backed counter, or a
   `Deferred` the body would complete).
2. Build the Command or Mount inside the test, including one whose body would
   throw, and drop it without returning it to a runtime.
3. Observe zero probe calls and no exception.

Fails on: an `execute` evaluated at construction, a removed `Effect.suspend`, a
browser global read while building a no-args `execute`.

## Mount, unmount, dispose

1. Start the application with `Runtime.embed` in a test container.
2. Give each Subscription Stream, ManagedResource release, and Mount finalizer a
   receipt (a `Deferred` completed in the release or finalizer).
3. Dispatch Messages that move the Model into the owning state, then out of it.
   Await the receipt; do not sleep.
4. Start an in-flight Command, call `dispose`, and await every remaining
   receipt. Observe that no Message dispatches after `dispose`.

Fails on: a listener or timer outside an owner, a fork detached from the runtime
scope, a release that is never registered because the resource was built before
the acquire body.

## Same key, repeated invocations

Dispatch the same interruptible Command twice under one key with gated Effects
(each waits on its own `Deferred`). Release both and observe both result
Messages. Then repeat and return the Interrupt: observe `Interrupted` and no
result Message from either holder.

Fails on: code that assumes a key serializes or replaces invocations.

## Cancel racing completion

1. Gate the Command's Effect on a `Deferred`.
2. Complete the gate so the result wins, then return the Interrupt.
3. Observe `NotFound` and the stated stale-result handling (the result is
   applied or dropped as the policy says, never both).
4. Repeat with the Interrupt first: observe `Interrupted` and no result.

Fails on: a policy that relies on arrival order, a result Message without the
identity update needs to recognise it.

## Cancel then replace

Return the Interrupt alone. Observe that the replacement Command appears only
in the Commands returned for `CompletedCancel<Name>` (a Story step can assert the
exact pending Commands at each point).

Fails on: `[Interrupt, Next]` returned in one batch.

## Page leaves, work stops

Dispatch the route change that unmounts a page with in-flight work. Observe
either the Interrupt Command in the returned Commands or the gated Subscription
or ManagedResource release receipt. Observe that a late result for the unmounted
child changes nothing.

Fails on: page-owned work that keeps running after the page is gone.
