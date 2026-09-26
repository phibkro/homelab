---
name: effect-resources-concurrency
description: Decides who owns every connection, subscription, process, lock, worker, and fiber in Effect v4 code, and states capacity, admission, ordering, overflow, and shutdown before choosing Queue, PubSub, or Semaphore. Use when acquiring resources, forking fibers, running background work, adding queues, locks, timers, or cancellation.
---

# Resources and concurrency

This skill owns two decisions: who owns each resource and each fiber, and what
capacity, order, and shutdown policy a concurrent path has. It prevents leaks on
interruption, work that outlives its owner, and queues or locks that promise
more than they give.

## Look up first

- `node_modules/effect/AGENTS.md` sections: "Managing resources and `Scope`s",
  "Running Effect programs", "Broadcasting messages with PubSub", "Working with
  Schedules", "Batching external requests".
- `node_modules/effect/ai-docs/src/01_effect/05_resources/` — `Effect.acquireRelease`
  inside a service layer, `Layer.effectDiscard` with `Effect.forkScoped` for
  background work, `LayerMap.Service` for keyed resources.
- `node_modules/effect/ai-docs/src/01_effect/06_running/` — `NodeRuntime.runMain`
  and `Layer.launch`: the process owns the root scope and turns SIGINT/SIGTERM
  into interruption.
- `node_modules/effect/ai-docs/src/01_effect/07_pubsub/`, `06_schedule/`,
  `05_batching/` — `PubSub.bounded` with a shutdown finalizer, `Schedule`
  composition, `RequestResolver` batching.
- `node_modules/effect/src/` module headers before you name a primitive:
  `Scope.ts`, `Fiber.ts`, `FiberSet.ts`, `FiberMap.ts`, `FiberHandle.ts`,
  `RcMap.ts`, `ScopedCache.ts`, `Pool.ts`, `Queue.ts`, `PubSub.ts`,
  `Semaphore.ts`, `PartitionedSemaphore.ts`, `Latch.ts`, `Deferred.ts`; the fork
  variants (`forkChild`, `forkScoped`, `forkIn`, `forkDetach`) in `Effect.ts`.
- `effect-house` for the repository's composition roots and test platform.

Stop searching when every primitive you will use has installed guidance or a
module header that states its capacity, ordering, and shutdown behaviour, or the
search established that none exists; say which in your report.

## Decide

1. **Write the ownership contract first.** For each connection, subscription,
   child process, lock, worker, and forked fiber, name the owner (request,
   session, layer, or process), the acquisition point, the release trigger, and
   the outcome on success, failure, and interruption.
2. **Map the owner to a native construct.**
   - Request or operation: `Effect.acquireRelease` under `Effect.scoped`, or
     `Effect.acquireUseRelease` when use is one step. Acquisition is
     uninterruptible by default; never acquire first and add a finalizer later.
   - Layer: acquire inside the layer constructor; background loops without a
     service interface use `Layer.effectDiscard` with `Effect.forkScoped`.
   - Process: `Layer.launch` run by the platform `runMain`.
   - Keyed family: `LayerMap.Service` for keyed services, `RcMap` for shared
     reference-counted resources (not a cache), `ScopedCache` for scoped values
     with expiry, `Pool` for interchangeable borrowed items.
3. **Tie every fiber to an owner.** `Effect.forkChild` ends with its parent;
   `Effect.forkScoped` and `Effect.forkIn` end with a scope; `FiberSet`,
   `FiberMap` (by key), and `FiberHandle` (at most one) own dynamic fibers.
   `Effect.forkDetach` has no owner and needs a written reason. A `FiberMap` or
   `FiberHandle` key is an address, not a lock: replacing a fiber signals the
   old one without waiting for its finalizers. When new work must start after
   cleanup, await `Fiber.interrupt` first.
4. **State the capacity policy before choosing a primitive**: capacity,
   admission (who may wait, how many), ordering (FIFO, per key, none),
   backpressure, overflow (suspend, drop newest, slide oldest, refuse), and
   shutdown (drain, cancel, or discard, with the documented outcome). Then pick:
   - One consumer per item: `Queue` (`bounded`, `dropping`, `sliding`).
     `Queue.end` completes after draining, `Queue.interrupt` refuses new offers
     and drains, `Queue.shutdown` discards buffered items.
   - Every subscriber sees every item: `PubSub` exposed as a `Stream` (see
     `effect-streams-protocols`).
   - Bounded use of a shared resource: `Semaphore` permits;
     `Semaphore.withPermitsIfAvailable` refuses instead of waiting;
     `PartitionedSemaphore` when groups must not starve each other; the
     `concurrency` option of `Effect.forEach` or `Stream.mapEffect` for fan-out.
   - Many callers for the same external data: `RequestResolver` batching.
   Bounded storage with unbounded waiting producers still admits unbounded work.
   Bound the waiters too: refuse, time out, or queue with a limit.
5. **Keep locks local unless storage coordinates.** `Semaphore`, `Latch`,
   `TxReentrantLock`, and queues serialize fibers of one process. Exclusion
   across processes, leases, and fencing belong to the database or a shared
   store (`effect-persistence-workflows`; the store-backed `RateLimiter` in
   `effect/unstable/persistence` limits across processes).
6. **Forward cancellation into foreign work.** Pass the `AbortSignal` that
   `Effect.tryPromise`, `Effect.promise`, and `Effect.callback` provide, or
   `Effect.abortSignal` in a scope; return a cleanup effect from
   `Effect.callback`. Interruption stops the waiting fiber, not foreign work
   that ignores the signal (`effect-boundary-adapters`). A child process that
   ignores SIGTERM survives scope close unless its kill options set
   `forceKillAfter`.
7. **Check the host boundary.** A foreign library that calls `process.exit` or
   detaches its own work skips your finalizers: OpenCode PR 51484 lost cleanup
   when a terminal spinner exited during an authorization wait. Route
   termination through `runMain` interruption.
8. **Time through Effect.** `Effect.sleep`, `Schedule` with `Effect.repeat`,
   `Effect.retry`, or `Effect.schedule`, and `Effect.timeout`. Never global
   timers: they escape interruption and `TestClock`.

## Rules

| Rule | Requirement | Enforcement |
|---|---|---|
| FX006 owned-lifetime | Every connection, subscription, process, lock, worker, and fiber has a named owner whose scope releases it once on success, failure, and interruption; layers are provided once at the composition root. | `effecttsgo/floating-effect`, `effecttsgo/multiple-effect-provide`, `effecttsgo/strict-effect-provide`; test: interruption before acquisition, while waiting, during use, and at completion releases each resource exactly once |
| FX003 owned-runtime-boundary | Background work is forked into an owner's scope (layer, fiber set, `runMain`), never started by running a runtime inside an effect. | `effecttsgo/run-effect-inside-effect`; test: closing the owning scope leaves no running fiber |
| FX009 explicit-order-capacity | Every queue, PubSub, semaphore, and concurrent batch states capacity, admission, ordering, backpressure, overflow, and shutdown before the primitive is chosen. | test: saturating the admission path shows the declared overflow outcome and a bound on active plus waiting work; test: shutdown with work in flight drains, cancels, or discards as documented |
| FX010 persistence-semantics | A local lock, semaphore, queue, or fiber serializes one process only; cross-process exclusion, leases, and fencing live in storage. | test: two processes against one disposable store keep the claim invariant; review-only |
| FX002 native-first | Timers, polling, retries, and cancellation signals use `Effect.sleep`, `Schedule`, `Effect.timeout`, and `Effect.abortSignal`. | `effecttsgo/global-timers`, `effecttsgo/global-timers-in-effect`, `effecttsgo/abort-controller-in-effect` |
| FX015 observable-tests | Concurrency tests synchronize on `Deferred`, `Latch`, or `TestClock`, and exercise cancellation through the real host boundary. | test: a host-level signal or unload runs every finalizer and leaves no permit, fiber, listener, or child process |

## Verify

- Interrupt at four points: before acquisition, while waiting (for a permit, a
  queue slot, or a foreign call), during use, and at completion. Each resource is
  released exactly once; no permit, fiber, listener, or child process remains.
- Synchronize with `Deferred` or `Latch` and move time with `TestClock.adjust`;
  a test that sleeps proves nothing about ordering (`effect-testing`).
- Same-key work excludes or serializes as the contract says; different-key work
  proceeds in parallel.
- Saturate the path: offer more work than capacity and observe the declared
  outcome (suspension, drop, slide, or refusal) and the bound on waiting work.
- Close the owning scope, or dispose the runtime, with work in flight; observe
  drain, cancel, or discard as documented.
- Host boundary: send the real signal, unload the plugin, or close the terminal;
  the finalizers run.
- Effect diagnostics are clean on the files you touched, at the severities
  `effect-house` records.
- Plausible bugs these checks catch: a finalizer added after an acquisition that
  was interrupted, a release that runs twice, producers that wait forever on a
  full queue, and an in-process lock presented as cross-process.

## Escape hatches

- `Effect.forkDetach` or a process-global resource is legitimate only when
  nothing can own it by design; the code names who stops it.
- A hand-rolled pool, lock, scheduler, or array of cleanup callbacks is a
  substitute. It needs a registered exception (`effect-review-exceptions`) with
  scope, missing capability, the native constructs examined (`Scope`, fiber
  sets, `RcMap`, `Pool`, `Queue`, `Semaphore`), verification (the tests above),
  owner, examinedWith versions, and retirement trigger.
- Not a justification: a primitive's name ("it is called a queue, so it is
  durable"), familiarity with another library, or not finding the API.

## Done means

- Every resource and fiber has a written owner, and a native construct enforces
  it.
- Every queue, PubSub, semaphore, and concurrent path has a stated capacity,
  admission, ordering, overflow, and shutdown policy, and a test observes it.
- No global timers, unowned forks, or runtimes started inside effects remain.
- Cross-process guarantees, if claimed, come from storage.
- The four-point interruption tests and the host-boundary test pass.
