---
name: effect-errors-recovery
description: Classifies Effect v4 failures (expected errors, defects, interruption, finalizer failures), defines typed tagged errors, recovers narrowly by tag or reason, translates them at semantic boundaries, and retries with bounded Schedules only when safe. Use when defining errors, wrapping throwing or rejecting code, adding catch, retry, or fallback logic, or mapping service errors to HTTP or RPC errors.
---

# Effect errors and recovery

This skill decides which failures are part of an operation's contract, how they
are typed, and which recovery is lawful. It prevents swallowed interruption and
defects, blanket fallbacks that hide real failures, retries of unsafe
operations, and error channels erased to satisfy a type checker.

## Look up first

- `node_modules/effect/AGENTS.md` sections: "Error handling" (with "Error
  handling basics"), "Working with Schedules", "Writing `Effect` code" (always
  `return yield*` when raising).
- `node_modules/effect/ai-docs/src/01_effect/04_errors/` — `Schema.TaggedError`,
  `Effect.catchTag`, `Effect.catchTags`, reason errors with `Effect.catchReason`,
  `Effect.catchReasons`, `Effect.unwrapReason`.
- `node_modules/effect/ai-docs/src/06_schedule/` — `Schedule` constructors,
  composition, `Effect.retry`, `Effect.repeat`.
- `node_modules/effect/ai-docs/src/01_effect/01_basics/10_creating-effects.ts` —
  `Effect.try` and `Effect.tryPromise` with a `cause: Schema.Defect()` field.
- `node_modules/effect/ai-docs/src/51_http-server/fixtures/` — errors with an
  HTTP status annotation and handlers that decide which service errors an
  endpoint declares.
- JSDoc in `node_modules/effect/src/Effect.ts` (`retry`, `promise`,
  `catchCause`, `ignore`, `ignoreCause`), `src/Cause.ts`, `src/Schedule.ts`.

Stop searching when every API you will use has matching installed guidance, or
the search established that none exists (then say so in your report).

## Decide

1. **Classify each failure before writing a handler.**
   - *Expected failure*: part of the contract; a caller can act on it (not
     found, conflict, invalid input, rate limit). Typed in the error channel.
   - *Defect*: a bug or broken invariant nobody can act on. It lives in the
     `Cause`, not in the error channel (`Effect.die`, `Effect.orDie`).
   - *Interruption*: a caller or parent cancelled. Not a failure to recover.
   - *Finalizer failure*: a release action has no typed error channel, so a
     failing finalizer becomes a defect. Make finalizers total and log inside
     them.
   One condition can be expected in one layer and a defect in another: the
   installed SQL example turns database failures into defects inside a
   repository whose contract promises only domain errors.
2. **Define expected errors** with `Schema.TaggedError`: a tag plus the fields a
   handler needs. A foreign cause goes in a `cause` field (`Schema.Defect()`),
   kept for diagnosis, not for branching. When a service would expose many tags,
   group them under one error with a tagged `reason` field.
3. **Map foreign failures where they enter.** `Effect.try` and
   `Effect.tryPromise` take a `catch` that returns a tagged error. `Effect.promise`
   is only for Promises that never reject; a rejection there becomes a defect.
   No `try`/`catch` inside a generator. SDK adapters: `effect-boundary-adapters`.
4. **Raise with `return yield*`** of the error value so the generator stops.
   The error channel never holds an Effect.
5. **Recover narrowly.** Handle only what the contract allows: `Effect.catchTag`
   or `Effect.catchTags` for tags, the reason APIs for reason errors. An absent
   directory may mean an empty listing; a permission error does not.
   `Effect.catch` handles every expected error, so use it only when every member
   of the error type has the same recovery. Ignoring a result is a named,
   logged decision for best-effort work only.
6. **Translate at semantic boundaries only.** Services keep domain errors. The
   HTTP or RPC handler decides which become declared endpoint errors and which
   become defects, as the installed HttpApi fixture does. Services never import
   transport error types; intermediate functions do not re-wrap.
7. **Retry only when safe.** The operation is idempotent or compensated, and the
   failure is retryable. Build the policy with `Schedule`: bound the attempts
   (`Schedule.recurs` combined through `Schedule.max`, which continues only while
   all members continue; `Schedule.min` continues while any member does and caps
   nothing), filter on the error with `Schedule.while`, add jitter for shared
   backends. `Effect.retry` retries typed failures only; defects and
   interruptions are not retried. The last failure stays typed unless the
   contract makes it a defect. Retry across restarts: `effect-persistence-workflows`.
8. **Never turn interruption into success.** A handler over the whole `Cause`
   (`Effect.catchCause`, `Effect.exit`, `Effect.matchCause`, `Effect.ignoreCause`)
   re-propagates interrupts (`Cause.hasInterrupts`, `Effect.failCause`). Cleanup
   belongs in finalizers (`Effect.ensuring`, `Effect.onInterrupt`), not in a
   catch-all.
9. **Never erase the error type** with a cast, an annotation that drops it, or
   `Effect.orDie` used only to satisfy a signature.

## Rules

| Rule | Requirement | Enforcement |
|---|---|---|
| FX005 honest-error-channel | Expected failures are `Schema.TaggedError` classes with the data a handler needs and any foreign cause in a `cause` field; the error channel never holds the global `Error`, a string, `unknown`, or `any`. | `effecttsgo/extends-native-error`, `effecttsgo/global-error-in-effect-failure`, `effecttsgo/any-unknown-in-error-context` |
| FX005 honest-error-channel | Foreign failures become typed errors where they enter, in the `catch` of `Effect.try` or `Effect.tryPromise`; generators contain no `try`/`catch`. | `effecttsgo/global-error-in-effect-catch`, `effecttsgo/unknown-in-effect-catch`, `effecttsgo/try-catch-in-effect-gen` |
| FX005 honest-error-channel | Errors are raised with `return yield*` so control flow ends; the error channel never holds an Effect. | `effecttsgo/missing-return-yield-star`, `effecttsgo/effect-in-failure` |
| FX005 honest-error-channel | Recovery names the tags or reasons the contract allows; no handler on an effect that cannot fail; no blanket recovery to a default or to void. | `effecttsgo/catch-unfailable-effect`, `effecttsgo/catch-to-ignore`, `effecttsgo/catch-tag-to-catch-reason`; test: each unhandled tag, a defect, and an interruption still reach the caller |
| FX005 honest-error-channel | Interruption is never recovered into success; handlers over the whole `Cause` propagate interrupts. | test: interrupting the operation mid-flight yields an interrupted exit, not a fallback value |
| FX005 honest-error-channel | The error type is never erased by a cast, an annotation, or `Effect.orDie` used only to satisfy a signature. | `effecttsgo/unsafe-effect-type-assertion`, `effecttsgo/missing-effect-error` |
| FX005 honest-error-channel | Service errors become transport errors only in the handler that owns the transport; services never import transport error types. | review-only |
| FX010 persistence-semantics | Retry only idempotent or compensated operations, only for retryable failures, with a bounded `Schedule`; the final failure stays typed. | test: a non-retryable failure runs once; a retryable one stops at the cap under `TestClock`; a non-idempotent mutation is not replayed without its idempotency key |
| FX011 intentional-observability | Errors carry the identifiers an operator needs, secrets stay `Redacted`, and a cause is logged once, where it is handled. | review-only |

## Verify

- For each operation: inject every expected tag, a defect, an interruption during
  the work, and a failure inside a finalizer. Assert the caller-visible exit
  (typed failure, defect, or interrupt) and the retained context (tag fields,
  `cause`).
- Recovery tests prove the handled tag recovers and every other tag still fails.
  A plausible bug this catches: an `Effect.catch` that also swallows a permission
  error.
- Retry tests run under `TestClock`: attempt counts, delays, the cap, and that a
  non-retryable tag is not retried.
- Type tests or compile checks show the error type after recovery is exactly the
  unhandled remainder.
- The Rules diagnostics are clean on the changed files. Test harness details:
  `effect-testing`.

## Escape hatches

Converting an expected failure into a defect is legitimate when the operation's
contract classifies it as unrecoverable, and the conversion sits at that
contract's boundary; it needs no exception but a reason a reviewer can read. A
foreign API whose error taxonomy or cancellation is unknown needs probes before
you invent tags (see `effect-boundary-adapters`). A substitute retry engine or
error library needs a registered exception per `effect-review-exceptions`
(scope, missing capability, native alternatives examined, verification, owner,
examinedWith versions, retirement trigger). Not a justification: "the caller
never handles it anyway", "the type was too long", or not finding the recovery API.

## Done means

- Every failure in the change is classified; expected ones are tagged errors in
  the error channel.
- Foreign failures are mapped where they enter; no `try`/`catch` in generators.
- Recovery names tags or reasons; translation happens only at the transport
  handler.
- Interruption and defects reach the caller unchanged; retries are bounded,
  filtered, and safe.
- Tests cover each tag, a defect, interruption, and retry limits; the Rules
  diagnostics are clean.
