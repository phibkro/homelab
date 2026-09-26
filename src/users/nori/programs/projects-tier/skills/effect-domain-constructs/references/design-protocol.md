# Design protocol: a domain construct without a second runtime

A worked example for `effect-domain-constructs`. Names are placeholders for a
domain, not an API. Look up every Effect API in the installed
`node_modules/effect/AGENTS.md`, `ai-docs/src`, and source before you use it.

## The domain

An application imports a file of structured facts: it reads the source,
decodes each record, persists accepted facts, and reports progress. The name
"import job" is useful. It does not by itself justify a job runtime.

## 1. Write the required behaviour first

- Construction is inert: building or discarding an import does nothing.
- The input source belongs to the import and is released when it ends.
- The caller can cancel; cancellation releases the source and sends no success
  receipt.
- Concurrency and waiting work are bounded.
- Invalid records follow one chosen policy: fail fast, or collect rejections.
- Retrying persistence has a stated idempotency rule.
- Success distinguishes committed facts from notifications published later.

## 2. Data and pure semantics

Schemas describe the request, the source identifier, the record format, the
domain fact, and the receipt. Alternatives are tagged: rejected record,
accepted record, completed import, interrupted import. Normalization and
aggregation are plain total functions. Decoding happens once, where records
enter (`effect-domain-models`).

## 3. Capabilities

The operation's contract names three channels: the receipt it returns, the
failures a caller can act on (decode failure, persistence failure), and the
capabilities it needs (a source reader, a fact store). The source reader owns
opening and reading; the fact store owns persisting a batch under its
transaction and idempotency contract. Infrastructure supplies both through
layers; tests supply deterministic ones through the same interfaces
(`effect-services-layers`). A storage SDK's Promise API stays inside the store
adapter, which maps its errors and forwards cancellation where the SDK
supports it (`effect-boundary-adapters`).

## 4. Native composition before abstraction

The first version is a direct program: acquire the source in a scope, stream
records, decode, persist with bounded concurrency, report progress, release.
Choose a queue only when admission must be decoupled from consumption.

Extract a combinator only when the same policy repeats: bounded traversal,
rejection accumulation versus fail fast, progress accounting, cancellation. It
keeps the error and requirement channels of what it wraps unless it handles or
provides them on purpose. If the direct program is small, keep it; a named
helper can serve the caller without a service.

## 5. Description plus interpreter, only when needed

A data description of validated import steps earns its place when a user must
preview the plan, when the plan must be persisted and resumed, or when a live
and a dry-run interpreter must both exist. Persist domain data and protocol
state (cursor, committed batch ids), never closures or Effect values. A local
fiber tree is not a recovery log; crash recovery is designed at the durable
boundary (`effect-persistence-workflows`).

## 6. Laws and the test that observes each

| Law | What the test does |
|---|---|
| Construction | Build and discard an import with a side-effect spy and a throwing setup; neither runs. |
| Channels | Type tests: a missing store is a compile error; handled failures leave the error type, unhandled ones stay. |
| Ownership | Finish, fail, and cancel an import; the source is released exactly once in each case. |
| Admission | Offer more work than the bound; active plus waiting work never exceeds it, including producers waiting outside the queue. |
| Cancellation | Cancel mid-import; no success receipt; committed batches and the resume cursor match the contract. |
| Durability | Crash between commit and publication; replay publishes each committed fact at most as often as the idempotency rule allows. |
| Equivalence | The construct and the direct composition agree on output, failures, requirements, resource use, and cancellation. |
| Substitution | Test layers replace the source and the store; domain code is unchanged; no global runtime is created. |

## 7. Rule for adding a primitive

Write the native composition, find the repeated law or the genuinely missing
capability, then name it. A construct that hides failures, requirements, or
ownership has not earned its place.
