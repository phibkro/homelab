# Effect-first pattern map

Consult the exact installed Effect v4 source before using an API name. This map describes semantic replacements, not copy-paste signatures.

Push dependencies outward without pushing Effect out of the core:

```text
portable Effect program
  requires abstract Services
           ↓ provide
Layer implementations
  import concrete runtimes and vendors
           ↓ select and run
composition root
```

A direct total function is still part of the portable program. A Service earns
its place by representing a dependency, authority, replaceable policy, or owned
lifecycle—not merely because a function exists.

| Plain JavaScript pattern | Effect-first default | Boundary reason |
| --- | --- | --- |
| `JSON.parse` plus a cast | `Schema.fromJsonString` and strict decoding | Syntax and semantic validation become one explicit codec |
| manual validator or switch over external tags | `Schema.Union`, tagged schemas, and Schema transformations | The accepted representation is inspectable and reusable |
| `process.env` or `Bun.env` across modules | Config descriptions provided at the root | Configuration authority and failure stay visible |
| singleton client | service contract plus Layer | Construction, replacement, and ownership are explicit |
| `throw`, broad `catch`, rejected Promise | tagged error channel and boundary error mapping | Expected failure remains typed and composable |
| `try/finally` resource protocol | scoped acquisition and release | Interruption cannot silently bypass release |
| `Promise.all` | Effect traversal with explicit concurrency | Concurrency and cancellation are bounded |
| `Promise.race` | Effect race with defined loser interruption | The losing computation has lifecycle semantics |
| `setTimeout`, `setInterval` | Clock, Schedule, Fiber, Stream, or XState callback actor | Time is a capability with an owner |
| hand-written retry loop | Schedule | Backoff, recurrence, and termination are values |
| mutable module variable | Ref, synchronized Ref, STM, or an owning actor | Mutation has one coordination model |
| `EventEmitter` | PubSub, Queue, Stream, or XState actor messages | Delivery and subscriber lifecycle are explicit |
| raw `fetch` | typed HTTP client/API boundary | Request, response, decoding, and errors share a contract |
| ad hoc REST types | Effect HTTP API, RPC, or generated schema contract | Client/server representations remain synchronized |
| direct database driver calls in domain code | Effect SQL service and transaction boundary | Persistence authority and failure remain injectable |
| command parser plus ambient exits | Effect CLI and one composition root | Arguments, help, Config, and exit behavior are modeled |
| `console.*` in operations | Effect logging, Console service, tracing, or injected telemetry | Observability is a capability |
| component `useEffect` for polling/subscriptions | XState callback actor or maintained query subscription | Lifecycle and cleanup are part of the state system |
| manual `useMemo` / `useCallback` everywhere | React Compiler | Optimization does not distort product semantics |

## Staged Schema composition

Model divide-and-conquer decoding as a pipeline of representations:

```text
external text
  -> lexical pieces
  -> structurally valid fields
  -> normalized domain values
  -> warranted program input
```

Give each arrow a named Schema transformation. In Effect v4, verify whether `Schema.decodeTo` or a specialized transformation expresses the direction. Preserve both the encoded and decoded type at every stage. This is the v4 continuation of the readable `Schema.compose` style used in earlier AoC solutions.

## UI lifecycle example

For a remote observation:

```text
XState custody actor
  hydrating -> refreshing -> resolving
     |             |            |
 cache Effect   fetch Effect   Schema / history checks
     v             v            v
 current | stale | offline | invalid | update-available
```

The machine owns polling, browser events, cancellation, adoption, and cleanup. Effect owns cache/fetch/decode computations. React renders the machine snapshot. TanStack Query can replace the fetch/cache portion when its ordinary server-state semantics are sufficient; do not run two competing owners.
