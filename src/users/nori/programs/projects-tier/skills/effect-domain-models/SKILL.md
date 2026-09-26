---
name: effect-domain-models
description: Models Effect v4 domain data with Schema. Decides who decodes untrusted input once, encoded versus domain types, branded ids, tagged unions, DateTime instead of Date, Predicate guards, codec laws, and persisted-shape migrations. Use when defining or changing schemas, ids, commands, events, stored records, or any code that parses external data.
---

# Effect domain models

This skill decides where untrusted data becomes a typed domain value and how
Schema represents it. It prevents three failures: casts and ad hoc parsers that
carry unvalidated data inward, repeated validation of data that is already
trusted, and codecs whose laws nobody states or tests.

## Look up first

- `node_modules/effect/AGENTS.md` sections: "Defining schemas and domain
  models", "Working with DateTime", "Runtime type guards", "Working with SQL
  databases".
- `node_modules/effect/ai-docs/src/01_effect/02_schema/` — `Schema.Class`, the
  `Type` and `Encoded` members, decoders built once and reused.
- `node_modules/effect/ai-docs/src/07_datetime/` — `DateTime.now` from the
  Clock, safe parsing with `DateTime.make`, time zones.
- `node_modules/effect/ai-docs/src/10_predicate/` — `Predicate` guards and
  their composition.
- `node_modules/effect/ai-docs/src/40_sql/` — branded ids with `Schema.brand`,
  `Model.Class` variants for database and JSON, migrations.
- The SCHEMA.md guide that AGENTS.md links. It lives on GitHub `main` and can be
  ahead of the installed release; read it in chunks, and when it disagrees with
  `node_modules/effect/src/Schema.ts`, the installed source wins.
- JSDoc in `node_modules/effect/src/Schema.ts`, `SchemaGetter.ts`, `DateTime.ts`,
  `Predicate.ts`, and `src/testing/TestSchema.ts` for exact decode and encode
  behaviour, normalization, and round-trip gotchas.

Stop searching when every API you will use has matching installed guidance, or
the search established that none exists (then say so in your report).

## Decide

1. **Find the trust boundary.** List every source of unknown data: request
   bodies and parameters, storage rows and documents, queue messages,
   environment, third-party responses, `JSON.parse` output. The component that
   receives the data owns its decoding. It decodes once and passes the domain
   type inward. A type argument, a cast, a generic `read<T>`, or a static
   interface validates nothing (the pack's OpenCode beta storage sample cast
   decoded JSON to `T` this way).
2. **Use the decoder the boundary already has.** HttpApi endpoints, RPC
   groups, `SqlSchema` queries, `Model.Class` repositories, and `Config` decode
   with the schema you give them. Do not decode again in the handler. Foreign
   SDK data follows `effect-boundary-adapters`.
3. **Separate representations where they differ.** One schema has an `Encoded`
   side (wire or storage shape) and a `Type` side (domain shape): dates, ids,
   optional versus `null`, amounts. For database and JSON variants of one
   entity, use `Model.Class`. Do not widen the domain type to fit the wire.
4. **Put local invariants in the schema.** Branded ids (`Schema.brand`),
   finite numbers (`Schema.Finite`), non-empty strings, literal sets
   (`Schema.Literals`). Invariants across records (uniqueness, references,
   allowed lifecycle transitions) belong to an operation or a storage
   constraint, not to a brand.
5. **Model alternatives as tagged unions.** Lifecycle states, commands, and
   events are tagged members (`Schema.TaggedStruct`, `Schema.TaggedUnion`,
   `Schema.TaggedClass`) matched exhaustively, not optional fields and flags.
6. **Choose the decoder by position.** Inside Effect code use the
   Effect-returning decoders: `Schema.decodeUnknownEffect` for `unknown` input,
   `Schema.decodeEffect` when the input already has the `Encoded` type. Build
   each decoder once. Synchronous decoders throw `SchemaError`; keep them for
   non-Effect code. Construct values through the schema (`make`, `makeEffect`).
7. **Decode with effects only when a transformation needs them.** A lookup or a
   Clock default makes the schema carry `DecodingServices`; provide them where
   you decode (look up `SchemaGetter.transformEffect`, `SchemaGetter.checkEffect`).
   Otherwise transformations stay synchronous.
8. **Time.** Read the current time with `DateTime.now` (Clock-backed, so
   `TestClock` controls it). Parse with `DateTime.make` or a DateTime schema such
   as `Schema.DateTimeUtcFromString`. No `Date.now()` or `new Date()`.
9. **Guards.** For narrowing that is not decoding, use `Predicate` helpers
   (`Predicate.isObject`, `Predicate.isTagged`, composed with `Predicate.and`,
   `Predicate.or`, `Predicate.not`) or `Schema.is`. Never write your own
   `isRecord` or `isString`.
10. **Persisted shapes are untrusted on read**, even when this application
    wrote them. A shape change ships with a decoder that accepts every stored
    version (a union of versioned encoded shapes that decodes into the current
    type through `Schema.decodeTo`) or with a data migration. SQL schema changes
    go through the migrator (`Migrator` in `effect/unstable/sql`).
11. **Pure stays pure (FX014).** A total transformation of decoded values is a
    plain function: no Effect, no service, no error channel, no re-validation.

## Rules

| Rule | Requirement | Enforcement |
|---|---|---|
| FX004 typed-boundary | The component that receives unknown data decodes it once with a schema and passes the domain type inward; a cast, type argument, or `JSON.parse` result never stands in for a decoded value. | `effecttsgo/prefer-schema-over-json`; test: malformed input at the boundary yields a typed decode failure, never a trusted value |
| FX004 typed-boundary | `Encoded` and `Type` stay distinct where they differ; `unknown` input uses the unknown decoder at the trust boundary, already-encoded input uses the typed decoder. | `effecttsgo/prefer-typed-schema-decoder`; review-only for the boundary placement |
| FX004 typed-boundary | Stored data is decoded on read like any external input; each persisted shape change ships with a versioned decoder or a migration. | test: a fixture of every stored version decodes to the current domain type |
| FX005 honest-error-channel | Inside Effect code, decoding uses the Effect-returning APIs so failures stay typed; no cast narrows the decode failure away. | `effecttsgo/schema-sync-in-effect`, `effecttsgo/unsafe-effect-type-assertion` |
| FX002 native-first | Alternatives and lifecycle states are tagged unions, literal sets are one literal schema, ids are branded, domain numbers are finite. | `effecttsgo/schema-struct-with-tag`, `effecttsgo/schema-union-of-literals`, `effecttsgo/schema-number` |
| FX002 native-first | Schema classes construct through the schema: no overridden constructor, no instance members on an opaque schema. | `effecttsgo/overridden-schema-constructor`, `effecttsgo/schema-opaque-instance-member` |
| FX002 native-first | Runtime checks use `Predicate` helpers or `Schema.is`; no hand-written `isRecord` or `isString`, no `instanceof` on a schema class. | `effecttsgo/instance-of-schema`; review-only for hand-written guards |
| FX002 native-first | Current time comes from `DateTime.now` or `Clock`; instants are `DateTime` values with DateTime schemas at the edges. | `effecttsgo/global-date`, `effecttsgo/global-date-in-effect` |
| FX014 pure-domain-core | Total transformations of decoded values stay plain functions with no Effect wrapper, service, or error channel; decoding is effectful only when a transformation needs a service. | review-only |
| FX015 observable-tests | Codec tests assert the law that holds: decode after encode returns the domain value; encode after decode returns the input only for canonical input; normalization is idempotent. | test: property tests over schema-generated values for each stated law |

## Verify

- Boundary tests: one valid input and each class of invalid input (missing
  field, wrong type, out of range, unknown tag, `null` where absence is
  expected). Assert the typed failure, not only that decoding failed.
- Law tests: `TestSchema.Asserts` in `effect/testing` (`verifyLosslessTransformation`
  checks decode after encode over generated values; `decoding()` and
  `encoding()` pin cases) and `it.effect.prop` with schema arbitraries. Never
  assert that encode after decode is identity for a normalizing codec:
  `Schema.DateTimeUtcFromString` normalizes offsets to UTC, and the
  `Schema.Defect` JSDoc lists values that do not round-trip.
- Migration tests: one fixture per stored version; each decodes to the current
  type; the encoder writes only the current version.
- Time-dependent code runs under `TestClock` and asserts exact instants.
- The diagnostics in Rules are clean on the files you changed (`effect-house`
  names where they run). Test harness details: `effect-testing`.

## Escape hatches

Legitimate cases are narrow: a generated client whose typed responses you still
decode in its adapter, or a measured hot path that skips an identity encode
(FX016; the pack's T3 selective-encoding change needed generated equivalence and
mutation checks). Each needs a registered exception per
`effect-review-exceptions`: scope, missing capability, native alternatives
examined, verification, owner, examinedWith versions, retirement trigger. Not a
justification: "the type already says so", "our own service wrote it",
familiarity with another validation library, or not finding the Schema API.

## Done means

- Every source of unknown data in the change has one named decoder at its
  boundary; nothing further in re-decodes or casts.
- `Encoded` and `Type` are distinct where they differ; ids are branded;
  alternatives are tagged unions.
- Time comes from `DateTime` or `Clock`; guards come from `Predicate` or
  `Schema.is`.
- Stored-shape changes have a versioned decoder or migration and a fixture per
  version.
- Codec tests state which law holds and pass; the Rules diagnostics are clean.
