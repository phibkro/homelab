---
name: effect-streams-protocols
description: Chooses the native Effect v4 protocol model (Stream, HttpClient, HttpApi, RPC, Socket, child process, CLI, AI, cluster) and specifies subscription start, replay, completion, buffering, closing, and wire compatibility. Use when building or consuming HTTP APIs, RPC, sockets, SSE, NDJSON, child processes, CLIs, or any stream or subscription.
---

# Streams and protocols

This skill owns two decisions: which native protocol model carries the data, and
what a subscription promises (start, replay, completion, failure, buffering, and
who closes it). It prevents hand-rolled clients and servers, undecoded frames,
leaked subscriptions, silent data loss, and wire breaks on upgrade.

## Look up first

- `node_modules/effect/AGENTS.md` sections: "Working with Streams", "Effect
  HttpClient", "Building HttpApi servers", "Working with child processes",
  "Building CLI applications", "Working with AI modules", "Building distributed
  applications with cluster".
- `node_modules/effect/ai-docs/src/03_stream/` — constructors (`Stream.callback`,
  `Stream.fromAsyncIterable`, `Stream.fromEventListener`, `Stream.paginate`,
  `Stream.fromEffectSchedule`), consumers (`Stream.runForEach`,
  `Stream.mapEffect` with `concurrency`), codecs (`Stream.pipeThroughChannel`
  with `Ndjson` and `SchemaBinary`).
- `node_modules/effect/ai-docs/src/50_http-client/` — `HttpClient` inside a
  service, `HttpClientResponse.schemaBodyJson`, `HttpClient.filterStatusOk`,
  `HttpClient.retryTransient`.
- `node_modules/effect/ai-docs/src/51_http-server/` and its `fixtures/` layout —
  API definitions (`fixtures/api`) apart from handlers (`fixtures/server`),
  `HttpApiClient.make`, `HttpApiTest.groups`, `HttpRouter.toWebHandler`.
- `node_modules/effect/ai-docs/src/60_child-process/`, `70_cli/`, `71_ai/`,
  `80_cluster/` — `ChildProcess` with `ChildProcessSpawner`; `Command`, `Flag`,
  `Argument`; `LanguageModel`, `Chat`, `Tool`, `Toolkit`; `Entity` with
  `Rpc.make`.
- `node_modules/effect/src/unstable/rpc/`, `socket/`, `encoding/` module
  headers (`RpcGroup`, `RpcServer`, `RpcClient`, `RpcSerialization`, `RpcTest`,
  `Socket`, `Sse`) and `src/Stream.ts` for `Stream.buffer`, `Stream.share`,
  `Stream.broadcast`, `Stream.fromPubSub`, and `Stream.toAsyncIterable`.

Stop searching when every API you will use has matching installed guidance, or
the search established that none exists; say which in your report. Modules under
`effect/unstable/*` change between releases: re-read their headers on upgrade.

## Decide

1. **Pick the protocol family by the requirement, not by familiarity.**

   | Requirement | Native family to look up |
   |---|---|
   | Call an external HTTP API | `HttpClient` service with a platform client layer |
   | Serve HTTP with schemas, OpenAPI, and a typed client | `HttpApi`, `HttpApiGroup`, `HttpApiEndpoint`, `HttpApiBuilder`, `HttpApiClient` |
   | Typed calls or streams between your own processes | `Rpc`, `RpcGroup`, `RpcServer`, `RpcClient` over HTTP, WebSocket, socket, worker, or stdio |
   | Raw bidirectional frames | `Socket` |
   | Server push to browsers | `Sse` over `HttpServerResponse.stream` |
   | Delimited or binary frames | `Ndjson`, `SchemaBinary` with `Stream.pipeThroughChannel` |
   | Run another program | `ChildProcess` with `ChildProcessSpawner` |
   | Command-line entry point | `Command`, `Flag`, `Argument` |
   | Language models | `LanguageModel`, `Chat`, `Tool`, `Toolkit` |
   | Stateful addressable services across machines | cluster `Entity` |

2. **Keep four things apart**: transport encoding (serializer, framing), domain
   schemas, operations (handlers implemented as services), and runtime binding
   (serve, `toWebHandler`, `Layer.launch`). API definitions import schemas only;
   clients import definitions, never server code.
3. **Derive clients from the contract.** Use `HttpApiClient.make` or `RpcClient`
   from the shared definition, or regenerate a generated SDK. Never hand-edit
   generated output; keep the repository's drift check (`effect-house`).
4. **Decode where the bytes arrive**: bodies with
   `HttpClientResponse.schemaBodyJson`, frames with `Ndjson.decodeSchemaString`
   or `SchemaBinary.decode`, payloads through endpoint schemas. No `JSON.parse`
   plus a cast (`effect-domain-models`).
5. **Specify every subscription.**
   - Start: a `Stream` is a description; each run subscribes anew.
   - Replay: none, a bounded in-memory window (`PubSub` replay, `Stream.share`),
     or a durable cursor.
   - Completion and failure: the producer ends with `Queue.end` inside
     `Stream.callback` and fails with a typed error.
   - Buffering: size and strategy (`Stream.callback` buffer options,
     `Stream.buffer`, the `PubSub` kind); `suspend` applies backpressure,
     `dropping` and `sliding` discard.
   - Who closes: the consumer's scope. Register the producer with
     `Effect.acquireRelease` inside `Stream.callback` so the listener goes away
     when the consumer stops.
6. **Hot broadcast is not a durable log.** `PubSub`, `Stream.share`,
   `Stream.broadcast`, and `SubscriptionRef` reach current subscribers; a replay
   window is bounded and lives in memory. When consumers need no gaps across
   restarts or reconnects, read durable history by cursor, switch to live
   events, and test the handoff (`effect-persistence-workflows`).
7. **Convert to foreign iterators only at the edge** (`effect-boundary-adapters`).
   `Stream.toAsyncIterable` (or `toAsyncIterableWith` when the stream needs
   services): early `return()` closes the stream's scope; a failure is thrown as
   a squashed cause, so map typed errors to values first when the consumer needs
   them; each new iterator runs the stream again. `Stream.fromAsyncIterable`
   calls `return()` on early close but cannot cancel a pending `next()`; build
   one-shot sources such as generators per run with `Stream.suspend`.
8. **Reconnect explicitly.** `Socket` reports every termination, clean closes
   included, as `SocketError`, so reconnecting is `Effect.retry` with a
   `Schedule` around the scoped consume loop. Decide what happens to in-flight
   messages.
9. **Treat an upgrade as a possible wire change.** LiveStore's move to Effect
   rc.113 replaced its MessagePack integration with `SchemaBinary` while method
   signatures stayed the same. Record the serializer in use (`RpcSerialization`
   offers JSON, NDJSON, JSON-RPC, and `layerSchemaBinary`), keep frames from the
   previous release as fixtures, and reject incompatible peers with a typed
   error.

## Rules

| Rule | Requirement | Enforcement |
|---|---|---|
| FX002 native-first | Use the installed protocol module (HttpClient, HttpApi, RPC, Socket, ChildProcess, CLI, AI, cluster) before another framework or a Node built-in. | `effecttsgo/global-fetch`, `effecttsgo/global-fetch-in-effect`, `effecttsgo/node-builtin-import` |
| FX004 typed-boundary | Decode every body, frame, and message with a schema at the protocol edge that receives it. | `effecttsgo/prefer-schema-over-json`; test: a schema-invalid frame fails with the typed decode error and reaches no domain code |
| FX003 owned-runtime-boundary | Handlers and clients return Effects; runtime binding (serve, `toWebHandler`, `runMain`) happens only at the entry point. | `effecttsgo/promise-in-effect-success`, `effecttsgo/run-effect-inside-effect` |
| FX006 owned-lifetime | Every subscription states who closes it; stopping the consumer releases the producer's listener, socket, or process exactly once. | test: early cancellation after one element releases the upstream registration once; finite and failing streams close once |
| FX009 explicit-order-capacity | Every stream buffer, PubSub, and concurrent mapping states capacity, strategy, and ordering. | test: a slow consumer observes the declared strategy (suspend, drop, slide) and bounded memory |
| FX010 persistence-semantics | A hot broadcast or replay window promises no durability and no gap-free history; history plus live needs a durable cursor. | test: subscribing during publication yields no gap and no duplicate across the history-to-live handoff |
| FX001 version-authority | An upgrade of Effect or a serializer is checked for wire changes before release. | test: frames recorded from the previous release decode, or fail with the declared incompatibility error |

## Verify

- Stream behaviour: finite, empty, and failing sources; a slow consumer; early
  cancellation (take one element, stop, observe the listener removed once); a
  reconnect; a schema-invalid frame.
- HttpApi handlers run through `HttpApiTest.groups`, which uses the same request
  encoding, routing, and response decoding without a server; cover error status
  mapping and middleware.
- RPC behaviour runs through `RpcTest`. It skips serialization, so add one test
  through the real `RpcSerialization` layer for the wire format.
- Child processes: assert the exit code; close the scope with the process
  running and observe no orphan.
- Foreign iterator edges: early `return()`, a consumer `throw()`, a rejected
  `next()`, and an already-aborted signal.
- Effect diagnostics are clean on the files you touched, at the severities
  `effect-house` records.
- Plausible bugs these checks catch: a listener never removed, a `dropping`
  buffer where loss was not allowed, a cast instead of a decode, and a serializer
  change that breaks old peers.

## Escape hatches

- A foreign protocol library is legitimate only for a concrete unsupported
  requirement (a transport or wire format no installed module provides) after
  the installed modules were checked. It lives in one adapter
  (`effect-boundary-adapters`) and needs a registered exception
  (`effect-review-exceptions`): scope, missing capability, native alternatives
  examined, verification, owner, examinedWith versions, retirement trigger.
- A hand-edited generated client is never an exception; regenerate it.
- Not a justification: familiarity with another framework, or a missing
  example for an `unstable` module that its source header documents.

## Done means

- The protocol runs on the native family for its requirement, with transport,
  schemas, operations, and runtime binding in separate modules.
- Every subscription has a written start, replay, completion, failure,
  buffering, and closing contract, and tests observe it.
- Every input is decoded at the edge; clients are derived or regenerated.
- Wire compatibility across the last upgrade is tested or explicitly rejected.
