---
name: effect-persistence-workflows
description: Names the durability guarantee before the machinery (command, durable fact, projection, external side effect; admitted, committed, projected, or externally completed receipts), then applies Effect v4 SQL, Model, transactions, idempotency keys, outbox queues, and durable workflows. Use when writing to a database, adding migrations, queues, workflows, or retries that must survive crashes.
---

# Persistence and workflows

This skill owns one question: what is durable, when, and what "done" means. It
prevents in-memory queues sold as durable acceptance, fibers sold as workflows,
lost or doubled side effects after a crash, and custom transaction services that
outlive the native support that replaces them.

## Look up first

- `node_modules/effect/AGENTS.md` sections: "Working with SQL databases",
  "Building distributed applications with cluster".
- `node_modules/effect/ai-docs/src/40_sql/10_basics.ts` — `Model.Class`
  variants, migrations through the driver's migrator (`fromRecord`,
  `fromFileSystem`), `SqlModel.makeRepository`, `SqlSchema.findAll`, and a
  repository service that hides `SqlClient`.
- `node_modules/effect/ai-docs/src/51_http-server/fixtures/` — one model feeding
  the `json`, `jsonCreate`, and `jsonUpdate` variants at the HTTP boundary, and
  an in-memory layer (`layerMemory`) for callers' tests.
- `node_modules/effect/ai-docs/src/80_cluster/10_entities.ts` — `Entity.make`,
  `ClusterSchema.Persisted` (messages are volatile by default),
  `TestRunner.layer`.
- `node_modules/effect/src/unstable/sql/` module headers: `SqlClient`
  (`withTransaction` uses savepoints when nested and rolls back on failure or
  interruption), `SqlError` (reasons such as `UniqueViolation`,
  `DeadlockError`, and `SerializationError`, each with `isRetryable`),
  `Migrator` (pending migrations run in a transaction; concurrent runs are
  locked), `SqlResolver`, `SqlSchema`, `SqlModel`.
- `node_modules/effect/src/unstable/workflow/` (`Workflow`, `Activity`,
  `DurableClock`, `DurableDeferred`, `DurableQueue`, `WorkflowEngine`),
  `src/unstable/cluster/ClusterWorkflowEngine.ts`, and
  `src/unstable/persistence/` (`PersistedQueue`, `Persistence`,
  `KeyValueStore`, `RateLimiter`).
- The installed driver package (`@effect/sql-pg`, `@effect/sql-sqlite-*`,
  `@effect/sql-d1`, ...) for its transaction support on the target platform;
  `effect-house` for the migrations location and the test database.

Stop searching when every API you will use has matching installed guidance, or
the search established that none exists; say which in your report.

## Decide

1. **Name the guarantee first.** Classify each write: command (a request that
   may be refused), durable fact (a committed row or event), projection (a
   derived read model that may lag), or external side effect (email, payment,
   third-party call). A receipt names exactly one milestone: admitted (validated
   and accepted), committed (in the database), projected (visible in the read
   model), or externally completed (the third party acknowledged). A success
   receipt does not prove exactly-once external execution.
2. **Keep the core pure.** Deciders (command and state to events or a rejection)
   and projections (a fold over events) are plain functions (FX014).
   Persistence wraps them.
3. **Store through schemas.** One `Model.Class` per table gives the select,
   insert, and update variants plus the JSON variants. Rows decode through the
   model (`SqlSchema`, `SqlModel.makeRepository`); JSON columns decode through a
   schema (`Model.JsonFromString`), never `JSON.parse` (`effect-domain-models`).
4. **Expose a repository narrower than SQL.** Domain code depends on a
   repository service with domain errors; SQL stays in its layer. Give callers
   an in-memory layer; test the SQL layer against a real disposable database.
5. **Draw the atomic boundary.** Wrap exactly the writes that must commit
   together in the client's `withTransaction` and state that boundary in the
   service contract. A rollback does not undo external side effects, so no
   external call runs inside a transaction. Retrying on a retryable `SqlError`
   reason re-runs the whole block.
6. **Coordinate in the database.** Store an idempotency key per command under a
   unique constraint and map `UniqueViolation` to the domain's "already done"
   outcome (`Effect.catchReason`). Claim work with conditional updates or row
   locks. An in-process `Semaphore` or queue does not coordinate two processes
   (`effect-resources-concurrency`).
7. **When commit and publication must survive a crash together**, choose one:
   - Outbox: write the fact and the outgoing message in one transaction; a
     worker publishes from it. `PersistedQueue` with an SQL store is built for
     outbox-style handoffs; delivery is at-least-once, so handlers are
     idempotent, and one instance runs `PersistedQueue.layerCleanup`.
   - Durable workflow: `Workflow` with `Activity` steps on a `WorkflowEngine`
     (`ClusterWorkflowEngine.layer` in production, `WorkflowEngine.layerMemory`
     for tests). Stored activity results replay after a crash; pass
     `Activity.idempotencyKey` to external APIs; use `DurableClock.sleep` for
     long waits, `Workflow.withCompensation` for undo steps, and `DurableQueue`
     for persisted workers.
   - Cluster entity messages that must survive restarts carry
     `ClusterSchema.Persisted`; `ClusterSchema.WithTransaction` is transactional
     only when the configured `MessageStorage` implements it.
   A fiber, `Queue`, or `PubSub` is none of these.
8. **Check platform transaction support.** Drivers differ per platform. DXOS
   removed its custom `SqlTransaction` service once Effect rc.115 added native
   Durable Object transactions, and only with the client configured with
   `storage: ctx.storage`, not `db: ctx.storage.sql` alone (FX012: retire a
   workaround when the native path passes its regression tests).
9. **Keep errors honest.** Expected constraint outcomes become domain errors;
   retryable reasons follow a stated `Schedule` or surface; stored data that
   fails to decode is a defect or a repair alarm, never "not found"
   (`effect-errors-recovery`).

## Rules

| Rule | Requirement | Enforcement |
|---|---|---|
| FX010 persistence-semantics | Each write names its guarantee and what its receipt means (admitted, committed, projected, externally completed); idempotency and cross-process coordination live in the database, not in fibers, queues, or local locks. | test: crash or interrupt before and after commit, and before and after external completion, then restart; state matches the receipt and a duplicate delivery produces one effect |
| FX004 typed-boundary | Rows, persisted JSON, and queue payloads decode through the model or a schema at the repository boundary. | `effecttsgo/prefer-schema-over-json`; test: a stored value that violates the schema fails with the typed decode error |
| FX005 honest-error-channel | Expected constraint outcomes map to domain errors; retryable `SqlError` reasons follow a stated retry policy or surface, never a success fallback. | test: a duplicate idempotency key yields the domain outcome; an injected retryable failure follows the declared schedule |
| FX009 explicit-order-capacity | Outbox and worker queues state ordering (global, per key, none), attempt limits, retry schedule, and dead-letter handling. | test: a poison item stops after the declared attempts while other items progress; per-key order holds with concurrent workers |
| FX014 pure-domain-core | Deciders and projections are plain functions of command, state, and events. | review-only |
| FX012 native-workaround-retirement | A custom transaction, queue, outbox, or serialization service is a registered exception, removed once the installed module covers it. | review-only; test: the workaround's regression suite passes on the native path before removal |
| FX015 observable-tests | Tests wait on receipts, worker drains, or durable-state queries, never on sleeps, and SQL semantics run on a disposable real database. | test: rollback, projection catch-up, and replay are asserted through the repository after the awaited receipt |

## Verify

- Crash points: stop the process or interrupt before commit, after commit but
  before publication, after publication but before acknowledgement, and after
  external completion but before it is recorded. After restart no fact is lost,
  no external effect runs twice, and every receipt matches durable state.
- Deliver the same message twice and replay a workflow: one effect.
- A failure and an interruption inside `withTransaction` leave no partial write.
- Rebuilding a projection from facts equals the incrementally built projection.
- Two workers against one disposable database keep the claim invariant.
- Migrations apply to an empty database and to a copy of the previous schema.
- Workflow logic runs on `WorkflowEngine.layerMemory`; a durability claim needs
  the real engine and storage.
- `effecttsgo/prefer-schema-over-json` is clean where persisted JSON is read.
- Plausible bugs these checks catch: a receipt sent before commit, an email
  inside a transaction that later rolls back, a retry that doubles a charge, and
  a projection that skips events at its cursor.

## Escape hatches

- A custom transaction, outbox, or lock service is legitimate only when the
  installed driver lacks the capability on the target platform. It needs a
  registered exception (`effect-review-exceptions`): scope, missing capability,
  native alternatives examined, verification (the tests above), owner,
  examinedWith (Effect and driver versions), and a retirement trigger such as
  "the driver release that adds the capability".
- Raw SQL inside the repository layer is normal; SQL outside it is a finding.
- Not a justification: "a fiber is simpler", "the outbox comes later" when the
  receipt already claims durability, or familiarity with another ORM.

## Done means

- Every write's guarantee and receipt milestone is written in the service
  contract.
- Repositories expose domain errors and decode through schemas.
- The atomic boundary is stated; no external call runs inside a transaction.
- Idempotency keys and database coordination cover multi-process writers.
- An outbox or durable workflow covers commit-and-publish paths.
- Crash-point, duplicate, rollback, and projection tests pass on a disposable
  database; obsolete workarounds are retired or registered.
