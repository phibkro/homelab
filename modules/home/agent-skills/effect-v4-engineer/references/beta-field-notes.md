# Field notes, verified against effect 4.0.0-beta.104

Observations from building on the v4 beta, each confirmed by running the code
rather than by reading documentation. Dates matter here: the beta moves weekly,
so treat every entry as evidence about a version, not a permanent truth.

## The ecosystem publishes v3 under `latest`

Three packages in one session resolved to a v3 line by default while a v4 line
existed under the `beta` dist-tag:

| Package | `latest` | v4 line |
| --- | --- | --- |
| `@effect/vitest` | `0.30.0`, peers `effect ^3.22` | `4.0.0-beta.104`, peers `vitest ^4.1` |
| `@effect/sql-d1` | `0.50.0` | `4.0.0-beta.104` |
| `drizzle-orm` Effect integration | targets v3 APIs | community patches only |

Check `dist-tags` and `peerDependencies` before installing anything from the
Effect ecosystem. `bun add` will otherwise quietly install a package that
cannot see your runtime.

## A declared peer range can be false

`alchemy@2.0.0-beta.45` declares `effect >= 4.0.0-beta.74 || >= 4.0.0`, and
breaks on beta.104:

```
TypeError: Schema.TaggedErrorClass is not a function
  at alchemy/src/Auth/AuthProvider.ts:32
```

`tsc --noEmit` passed the upgrade, because the dependency ships `.ts` sources
that `skipLibCheck` never checks. Only running the program revealed it. A
version range is a claim; executing the path is the evidence.

The practical consequence: a repository may legitimately hold two Effect
versions — one for the application, one for a tool that has not caught up.
Record why, so nobody tidies the split away.

## Renames confirmed by compiler error

| Reached for | Actually | Notes |
| --- | --- | --- |
| `Schema.ErrorClass` | `Schema.TaggedError<Self>()("Tag", fields)` | `Data.TaggedError` still exists for non-schema errors |
| `Context.Tag` | `Context.Service<Self, Shape>()("Id")` | identifier passed to the returned constructor |
| `Either` | `Result` | |
| `@effect/schema` | `effect/Schema` | core, not a package |
| `@effect/platform/HttpApi` | `effect/unstable/httpapi` | |
| Model helpers | `effect/unstable/schema/Model` | |

## HttpApi argument shapes differ per option

`params` and `query` accept a **field record**; `payload` requires a **schema**:

```ts
HttpApiEndpoint.post("save", "/api/v1/me/saved", {
  params: { id: Schema.String },                    // record
  payload: Schema.Struct({ jobId: Schema.String }), // schema
})
```

Passing a record as `payload` produces an overload error that names the first
field rather than the shape, which reads as a schema problem and is not one.

## Model is worth reaching for on SQLite

`Model.Class` generates `select`, `insert`, `update`, and the JSON variants from
one declaration. Four helpers remove code that caused real defects elsewhere:

- `Model.Sensitive` — present in database variants, **omitted from every JSON
  variant**, so personal data cannot reach a response by construction.
- `Model.BooleanSqlite` — `0 | 1` in the database, `boolean` in JSON.
- `Model.JsonFromString` — JSON columns without hand-written parse and stringify.
- `Model.DateTimeInsert` / `DateTimeUpdate` — timestamps without a clock at each
  call site.

Field **names** are readable at runtime (`Model.select.fields`), which is enough
to generate a column list. Encoded **types** are type-level only: there is no
runtime accessor, so DDL types must be declared and reviewed.

## Testing

- `@vitest/coverage-v8` cannot run under Bun. It drives Node's inspector and
  fails with `Coverage APIs are not supported`, then reports **"no tests"** —
  which reads like a broken suite rather than a missing capability. Use
  `@vitest/coverage-istanbul`, which instruments source.
- Doctests use ```` ```ts import.meta.vitest ```` blocks, run by vitest with
  `test.includeSource`. TypeScript needs `types: ["vitest/importMeta"]` or
  `import.meta.vitest` is an error.
- Extensionless relative imports fail under this setup; keep the `.ts`
  extension with `allowImportingTsExtensions`.
