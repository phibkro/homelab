---
name: effect-services-layers
description: Designs Effect v4 capabilities as Context.Service classes, their implementation layers and lifetimes, configuration, test substitutes, and the one composition root that runs them. Use when adding or changing a service, a layer, dependency wiring, configuration reads, a process entry point, or a framework runtime bridge.
---

# Effect services and layers

This skill decides which capability a service exposes, how its implementation
gets dependencies and resources, and where the graph is assembled and run. It
prevents leaked implementation requirements, per-call runtimes, late
`process.env` reads, duplicated or unowned resources, and services that wrap
pure functions.

## Look up first

- `node_modules/effect/AGENTS.md` sections: "Writing Effect services" (with
  "Context.Service"), "Running Effect programs", "Integrating Effect into
  existing applications", "Managing resources and `Scope`s".
- `node_modules/effect/ai-docs/src/01_effect/03_services/` — `Context.Service`
  with a static layer, `Context.Reference` for defaulted values,
  `Layer.provide` versus `Layer.provideMerge`, `Layer.unwrap` over `Config`.
- `node_modules/effect/ai-docs/src/01_effect/06_running/` — platform `runMain`
  and `Layer.launch` as process entry points.
- `node_modules/effect/ai-docs/src/04_integration/` — one `ManagedRuntime` for a
  framework host, a shared memo map, disposal on shutdown.
- `node_modules/effect/ai-docs/src/09_testing/20_layer-tests.ts` — test layers
  composed with `Layer.provideMerge`.
- JSDoc in `node_modules/effect/src/Layer.ts` (sharing by reference,
  `Layer.fresh`, `Layer.mock`), `src/Context.ts` (the key is the runtime
  identity), `src/Config.ts`, `src/ConfigProvider.ts`.

Stop searching when every API you will use has matching installed guidance, or
the search established that none exists (then say so in your report).

## Decide

1. **Is it a capability?** A service stands for an external system (database,
   HTTP API, file system), configuration, or an owned resource (pool, cache,
   worker). A pure deterministic function stays a function (FX014). A value with
   a sensible default (feature flag, tuning value) is a `Context.Reference`.
2. **Design the interface first.** Expose domain operations with precise
   success and error types. Every method requires nothing: dependencies are
   resolved when the layer is built. Do not hand out the vendor client or raw
   connection when callers need a narrower operation.
3. **Define it the installed way.** A `Context.Service` class whose string key
   includes the package and path (the key is the runtime identity; two services
   with one key collide), a static layer built with `Layer.effect`, methods
   written with `Effect.fn("Service.method")`, and the value returned through
   the class's `of`. Check `effect-house` for layer names (the installed
   examples use `layer`, `layerNoDeps`, `layerTest`).
4. **Lifetime.** `Layer.effect` runs in the layer's scope, so a resource
   acquired there with `Effect.acquireRelease` lives until the layer is torn
   down. Background work without an interface is `Layer.effectDiscard`; resources
   keyed by tenant or id are `LayerMap.Service`. Details: `effect-resources-concurrency`.
5. **Configuration.** Read `Config` values while the layer is built; choose an
   implementation with `Layer.unwrap`; secrets use `Config.Redacted`. No
   `process.env` in services and no configuration reads at call time.
6. **Graph.** `Layer.provide` satisfies a dependency and hides it;
   `Layer.provideMerge` satisfies it and also exposes it (tests that need the
   test store, the SQL example that exposes the migrated client);
   `Layer.mergeAll` joins independent layers only. A layer value is built once
   and shared by reference; `Layer.fresh` builds a separate instance on purpose.
   A layer may provide its private dependencies where it is defined, as the
   installed SQL and HttpApi examples do.
7. **Composition root.** One per process. A long-running application is a
   layer run with `Layer.launch` under the platform `runMain`. A framework host
   builds one `ManagedRuntime` from the application layer (several runtimes
   share one memo map from `Layer.makeMemoMapUnsafe`) and disposes it at
   shutdown. Service methods never run effects; host bridges belong to
   `effect-boundary-adapters`.
8. **Tests substitute through the interface.** A test layer, `Layer.mock` for a
   partial stub, and `ConfigProvider.layer` with `ConfigProvider.fromUnknown` for
   configuration. Domain code does not change.
9. **Contracts apart from implementations.** Schemas, HttpApi definitions, and
   RPC groups live where clients can import them without server code (the
   installed HttpApi example keeps API definitions separate from handlers).

## Rules

| Rule | Requirement | Enforcement |
|---|---|---|
| FX002 native-first | Each capability is a `Context.Service` class declaration whose `Self` matches the class and whose key follows the package-path form; services take no type parameters. | `effecttsgo/service-not-as-class`, `effecttsgo/class-self-mismatch`, `effecttsgo/deterministic-keys`, `effecttsgo/generic-effect-services` |
| FX006 owned-lifetime | Service methods require nothing; the layer resolves dependencies once at construction and owns what it acquires until its scope closes. | `effecttsgo/leaking-requirements`; test: an acquisition counter shows one acquisition per application and one release at shutdown |
| FX008 capability-preservation | The composed graph satisfies every requirement by providing it; interdependent layers are composed with provide, never merged; no cast removes a requirement. | `effecttsgo/missing-layer-context`, `effecttsgo/missing-effect-context`, `effecttsgo/layer-merge-all-with-dependencies`, `effecttsgo/unsafe-effect-type-assertion` |
| FX003 owned-runtime-boundary | One composition root per process provides the application layer and runs it; `Effect.provide` with a layer appears only at entry points and in tests, once per program. | `effecttsgo/strict-effect-provide`, `effecttsgo/multiple-effect-provide` |
| FX003 owned-runtime-boundary | Service methods return Effects; they never call `Effect.run*`, build a runtime, or return a Promise to leave the graph. | `effecttsgo/run-effect-inside-effect` |
| FX002 native-first | Configuration is read through `Config` while layers are built, implementation choice goes through `Layer.unwrap`, and defaulted values are `Context.Reference`; no `process.env` reads in services or at call time. | `effecttsgo/process-env`, `effecttsgo/process-env-in-effect` |
| FX014 pure-domain-core | A pure deterministic function stays a function; a service exists only for a capability, configuration, or owned resource. | review-only |
| FX015 observable-tests | Tests replace implementations through the service interface (test layer or `Layer.mock`) without changing domain code. | test: the same domain program passes against the test layer, and the live layer builds with every requirement satisfied |
| FX004 typed-boundary | Clients depend on shared contracts (schemas, HttpApi and RPC definitions), never on server implementation modules. | review-only |

## Verify

- The application layer and each entry point type-check with no unsatisfied
  requirement; the Rules diagnostics are clean on the changed files.
- Sharing: an acquisition counter in a test layer shows an expensive resource
  is acquired once even when several services depend on it, and released once
  at shutdown. A plausible bug this catches: an accidental `Layer.fresh`, or a
  layer rebuilt per request because it was provided inside a handler.
- Substitution: the domain program runs against the test layer and the live
  layer without source changes; a missing member of a `Layer.mock` fails loudly
  when exercised.
- Configuration: a test provides values through `ConfigProvider.layer` and
  asserts both the chosen implementation and the failure for a missing value.
- `run-effect-inside-effect` suggests `run*With` variants; inside a service the
  fix is to yield the effect instead.

## Escape hatches

A second runtime or a runtime inside a module is legitimate only at a real host
boundary that cannot receive the application runtime (a plugin ABI, a framework
callback); it follows `effect-boundary-adapters` and needs a registered
exception per `effect-review-exceptions` (scope, missing capability, native
alternatives examined, verification, owner, examinedWith versions, retirement
trigger). A custom service that stands in for a missing native capability
retires when the capability ships (the pack's DXOS migration removed its own
SqlTransaction service once rc.115 supported the platform natively). Not a
justification: "wiring is simpler this way", familiarity with another DI
container, or not finding the layer API.

## Done means

- Each new service stands for a capability, configuration, or owned resource,
  and its methods require nothing.
- Implementations acquire in their layer and release when its scope closes;
  shared resources are acquired once.
- Configuration flows through `Config` and `Context.Reference`, not `process.env`.
- One composition root per process runs the graph; no service method runs an
  effect.
- Test layers substitute through the same interface; the Rules diagnostics are
  clean.
