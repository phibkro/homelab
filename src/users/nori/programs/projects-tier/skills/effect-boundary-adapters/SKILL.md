---
name: effect-boundary-adapters
description: Contains unavoidable Promise, callback, SDK, DOM, and framework-handler APIs behind one small named adapter per boundary, with typed errors, decoded outputs, bridged AbortSignal cancellation, scoped registration, and one owned runtime bridge. Use when wrapping a foreign API, exposing Effect to a Promise or callback host, or embedding Effect in a framework.
---

# Boundary adapters

This skill decides whether a foreign interface is necessary and, when it is, how
one adapter module contains it. It prevents runtime laundering (run, get a
Promise, wrap it back into an Effect), lost cancellation, `unknown` errors,
unvalidated foreign data, and callbacks that outlive their owner.

## Look up first

- `node_modules/effect/AGENTS.md` sections: "Integrating Effect into existing
  applications", "Writing `Effect` code" (its "Creating effects from common
  sources" example), "Working with Streams".
- `node_modules/effect/ai-docs/src/01_effect/01_basics/10_creating-effects.ts` —
  `Effect.sync`, `Effect.try`, `Effect.tryPromise`, `Effect.fromNullishOr`, and
  `Effect.callback` returning a cleanup effect.
- `node_modules/effect/ai-docs/src/04_integration/10_managed-runtime.ts` — one
  `ManagedRuntime` built from the application layer, a shared memo map
  (`Layer.makeMemoMapUnsafe`), `runPromise`, `runSync`, or `runCallback` at the
  handler edge, and `dispose` on shutdown.
- `node_modules/effect/ai-docs/src/03_stream/10_creating-streams.ts` —
  `Stream.fromAsyncIterable`, `Stream.fromEventListener`, `Stream.callback`,
  `NodeStream.fromReadable`.
- `node_modules/effect/src/Effect.ts` for `Effect.tryPromise`, `Effect.promise`,
  and `Effect.callback` (each passes an `AbortSignal`), `Effect.abortSignal`,
  `Effect.acquireDisposable`, `Effect.runPromiseWith`, and the `signal` field of
  `Effect.RunOptions`; `src/FiberSet.ts` for `FiberSet.makeRuntimePromise`;
  `src/Stream.ts` for `Stream.toAsyncIterableWith` and `Stream.toReadableStream`.
- The installed platform packages (`@effect/platform-node`, `-bun`, `-browser`)
  before you adapt something they cover; `effect-house` for the repository's
  bridge module and composition roots.

Stop searching when every API you will use has matching installed guidance, or
the search established that none exists; say which in your report.

## Decide

1. **Prove the boundary is necessary.** Name the foreign ABI: a host that calls
   you with Promises or callbacks (plugin API, framework handler, worker
   message), an SDK without an Effect client, a DOM or browser primitive. Check
   the installed modules first: `HttpClient` instead of `fetch`; `FileSystem`,
   `Path`, and `ChildProcess` instead of Node built-ins; `Socket`; platform
   streams. Not recalling an API is not a capability gap.
2. **One small named module per boundary.** Only it imports the foreign
   package. It exports an Effect- and Schema-facing contract: a service whose
   methods return Effects with tagged errors, plus schemas for what crosses
   (`effect-services-layers`).
3. **Inbound: Effect calls the foreign API.**
   - Synchronous and cannot throw: `Effect.sync`. May throw: `Effect.try`.
     Promise: `Effect.tryPromise` with a `catch` that returns a tagged error.
     Callback: `Effect.callback` with a cleanup effect. Events or iterators:
     `Stream.callback`, `Stream.fromEventListener`, `Stream.fromAsyncIterable`,
     `Stream.fromReadableStream`. Disposable handles: `Effect.acquireRelease` or
     `Effect.acquireDisposable`.
   - Pass the provided `AbortSignal` into the foreign call, or use
     `Effect.abortSignal` for a scope-owned one. Never build an
     `AbortController` inside an effect.
   - Decode outputs whose shape the foreign side does not guarantee with
     `Schema.decodeUnknownEffect`. Never cast.
   - Map expected rejections to tagged errors; unexpected throws stay defects or
     keep the original as `cause` (`effect-errors-recovery`).
4. **Outbound: the host calls Effect.**
   - Build one runtime at the owned entry point: `ManagedRuntime.make` from the
     application layer for framework handlers; `FiberSet.makeRuntimePromise` in
     a scope you own when a plugin or host registers callbacks (closing that
     scope interrupts every fiber it started); `Stream.toAsyncIterableWith` for
     iterator ABIs; `HttpRouter.toWebHandler` for fetch-style hosts.
   - Pass the host's `AbortSignal` in the run options (`signal`) so host
     cancellation interrupts the fiber.
   - Map typed errors to the host's representation (status code, rejection
     shape) here and nowhere else. OpenCode's v2 Promise plugin adapter shows
     the shape: one module captures context, adapts streams to async iterables,
     tracks subscriptions for unload, bridges abort signals, and maps RPC errors.
5. **Never launder.** A service method that runs a runtime and wraps the Promise
   back loses interruption, context, and typed errors. Compose the Effects.
6. **Non-cancellable foreign work.** Interruption stops the waiting fiber, not
   the foreign operation. Say so in the adapter, bound the wait
   (`Effect.timeout`), make a late result harmless (no state mutation after the
   owner closed), and release what the late result holds.
7. **Casts** are legal only where the type system cannot express a local
   invariant, such as a heterogeneous registry. A comment states the invariant
   and a test covers it. Never cast to erase a requirement or to claim decoding.
8. **Plan removal.** When upstream support is plausible (a platform module, an
   SDK with Effect support), the adapter names the trigger that retires it.

## Rules

| Rule | Requirement | Enforcement |
|---|---|---|
| FX002 native-first | Adapt a foreign API only after the installed Effect and platform modules were checked for the capability. | `effecttsgo/global-fetch`, `effecttsgo/node-builtin-import`, `effecttsgo/async-function`, `effecttsgo/new-promise`; review-only for the necessity record |
| FX003 owned-runtime-boundary | One runtime bridge per owned entry point (`ManagedRuntime`, a `FiberSet` runtime, a web handler); domain code never runs a runtime and re-wraps the Promise. | `effecttsgo/run-effect-inside-effect`, `effecttsgo/promise-in-effect-success`, `effecttsgo/lazy-promise-in-effect-sync` |
| FX004 typed-boundary | Foreign outputs are decoded with a schema in the adapter; a cast needs a stated local invariant and a test. | `effecttsgo/prefer-schema-over-json`, `effecttsgo/unsafe-effect-type-assertion`; test: malformed foreign output fails with the typed decode error |
| FX005 honest-error-channel | Expected rejections map to tagged errors in `catch`; unexpected throws stay defects. | `effecttsgo/unknown-in-effect-catch`, `effecttsgo/global-error-in-effect-catch`; test: an expected rejection surfaces as the typed error and an unexpected throw as a defect |
| FX006 owned-lifetime | Cancellation reaches the foreign call through its `AbortSignal`; every registration is released once on every terminal event; late results mutate nothing. | `effecttsgo/abort-controller-in-effect`; test: interrupting while waiting aborts the foreign call and runs cleanup once |
| FX012 native-workaround-retirement | Each adapter names its foreign ABI and the upstream change that retires it. | review-only |
| FX016 lawful-performance-exception | A faster non-native path (skipped encoding, direct driver or SDK call) needs a measured unmet budget, exhausted native options, and an approved exception. | test: an equivalence check against the native path plus a benchmark against the stated budget; review-only for approval |

## Verify

- Cancellation reaches the foreign side: interrupt while waiting and observe the
  abort in a fake (it records `signal.aborted`) and cleanup exactly once.
- Every terminal event releases the registration once: success, typed failure,
  defect, interruption, early `return()` of an iterator, a consumer `throw()`,
  host unload, and a signal that was already aborted at entry.
- An expected rejection arrives as the typed error; an unexpected throw arrives
  as a defect (assert on the `Exit`, not on a message string).
- Malformed foreign output fails with the typed decode error.
- A late result after interruption changes no state.
- One test drives the real host (framework test client, plugin unload, process
  signal). OpenCode PR 51484 is the case: a terminal library called
  `process.exit` and bypassed correct finalizers.
- Effect diagnostics are clean outside the adapter; inside it, every remaining
  finding carries an exception ID.

## Escape hatches

- A host ABI that demands Promises or callbacks is a legitimate boundary. The
  adapter module is its record: the foreign ABI, the contract, the tests, and
  the removal trigger.
- An `async` function, `new Promise`, a second runtime, or a cast outside the
  adapter needs a registered exception (`effect-review-exceptions`): scope,
  missing capability, native alternatives examined, verification, owner,
  examinedWith versions, retirement trigger. Suppress with
  `// oxlint-disable-next-line <rule> -- EX-NNNN: <reason>`.
- Performance substitutes follow FX016. T3 PR 13767 skipped redundant Schema
  encoding only with generated equivalence and mutation checks; a reported
  speed-up alone does not qualify.
- Not a justification: familiarity, convenience, or not finding the API.

## Done means

- The foreign dependency is imported by one named module with an Effect- and
  Schema-facing contract.
- Cancellation, typed errors, decoding, and cleanup on every terminal event are
  tested, including one test through the real host.
- Domain code composes Effects with no runtime calls; the only runtime bridge
  sits at an owned entry point.
- The adapter names its removal trigger; every remaining suppression names an
  exception.
