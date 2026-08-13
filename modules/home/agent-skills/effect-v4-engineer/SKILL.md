---
name: effect-v4-engineer
description: Build, review, or migrate TypeScript systems that use Effect v4 as their default application language. Use for Effect v4 code, Schema boundaries and transformations, Config, services and Layers, Fiber and structured concurrency, streams, queues, RPC, HTTP API, SQL, CLI, React integration, Effect lint policy, or work where agents might otherwise fall back to ambient plain TypeScript patterns.
---

# Effect v4 Engineer

Use Effect as the application language and standard library. Push dependencies and authority to explicit seams: portable programs require abstract Services, Layer implementations lower those requirements into concrete runtimes, and composition roots select Layers and execute the program. A small total expression can remain a direct function; do not turn dependency-free computation into a Service merely for uniformity.

## Establish the exact API

1. Read the repository `AGENTS.md` and package manifests.
2. Record the exact `effect`, platform, and TypeScript versions. Treat every v4 prerelease change as potentially incompatible.
3. When the official Effect checkout is available at `../effect`, treat it as the authoritative feature reference: start at `LLMS.md`, then read the relevant package guide, source, tests, and type tests. Otherwise prefer the installed package source, README, and declarations over remembered v3 APIs.
4. Search the repository for accepted v4 patterns before introducing a new house abstraction.
5. Use [official-source-router.md](references/official-source-router.md) to load only the official source branches relevant to the task.
6. Read [effect-first-patterns.md](references/effect-first-patterns.md) before implementing or reviewing application architecture.
7. Read [beta-field-notes.md](references/beta-field-notes.md) before installing a dependency or upgrading the prerelease. It records renames confirmed by compiler error, ecosystem packages whose `latest` tag still points at v3, and a peer range that is declared satisfied and is not.

Never silently translate a v3 example. For example, staged Schema composition that used `Schema.compose` in older code is normally expressed with `Schema.decodeTo` or a specific v4 transformation. Verify the direction from the installed source.

Do not maintain a second catalog of Effect features in this skill. This skill
defines architectural policy and routes API questions to the official repository;
the checked-out source defines the available modules and exact signatures.

## Choose the semantic construct

- Model an ordinary boundary record with `Schema.Struct` and a same-name interface when the project uses that convention.
- Model an internal control-flow sum with `Data.TaggedEnum` and its exhaustive `$match`; do not add Schema only to obtain constructors and matching.
- Model a serializable or externally decoded sum with `Schema.TaggedUnion` and its `cases`, `guards`, and exhaustive `match` helpers.
- For an external discriminator other than `_tag`, build the member structs with `Schema.tag(...)` and add union helpers through `Schema.toTaggedUnion(discriminator)`.
- Model expected schema-visible Effect failures with `Schema.TaggedError<Self>()("Tag", fields)`. Verify this exact prerelease name; do not import the obsolete `TaggedErrorClass` spelling.
- Decode unknown input with `Schema.decodeUnknownEffect`. Use `schema.makeEffect` when construction failure belongs in the error channel; reserve throwing construction for trusted paths that intentionally terminate on invalid values.

## Classify each module

Assign one primary role before editing:

- `pure-library`: total deterministic values and algorithms, preferably using Effect's data modules where they fit;
- `schema-boundary`: encoded data, decoding, validation, and transformations;
- `effect-library`: reusable programs with requirements still visible;
- `service`: one owned capability exposed through a service contract and Layer;
- `application`: orchestration without closing all requirements;
- `composition-root`: the narrow place that chooses live Layers and runs Effect;
- `runtime-adapter`: Bun, browser, worker, database, or framework integration;
- `ui-machine`: XState transitions and observations connected to Effect computations.

Do not let a reusable library execute its own runtime or select live infrastructure.

## Implement Effect-first boundaries

### External data and representations

- Define an Effect Schema for every external, persisted, network, configuration, CLI, or public artifact boundary.
- Decode `unknown` with strict excess-property handling where a closed interface is intended.
- Use `Schema.fromJsonString`, `Schema.decodeTo`, and named transformations instead of raw parsing plus casts.
- Compose schemas as staged codecs. Each stage should expose the representation it accepts and the representation it guarantees.
- Keep encoded and decoded types distinct. Do not use `as` to pretend a crossing was checked.
- Generate JSON Schema or API documentation from the canonical schema when consumers need a contract.

### Capabilities and configuration

- Read configuration through Effect Config. Do not read ambient environment variables throughout the program.
- Model clocks, randomness, files, network clients, persistence, and operational output as requirements or services.
- Search Effect's core, platform, and unstable modules before defining a project Service. Reuse services such as FileSystem, Path, ChildProcessSpawner, HttpClient, and their platform Layers when they already express the required capability.
- Define a project Service when it owns a domain contract, policy, or capability that is meaningfully different from the existing Effect service—not merely to rename a platform operation.
- Keep concrete runtime, vendor, and operational imports inside runtime adapters that implement those Services.
- Build adapters as Layers. Provide final live Layers only at the composition root.
- Prefer existing Effect platform modules and maintained adapters over custom wrappers.

### Failure and resources

- Represent expected failure in the typed error channel with small tagged errors.
- Map platform defects into domain errors at the boundary that understands them.
- Use scoped acquisition and release for resources. Do not emulate ownership with scattered `try/finally` blocks.
- Preserve causes when translating errors. Do not reduce structured failures to anonymous strings prematurely.

### Concurrency and state

- Use Effect Fiber and structured concurrency for bounded lifetimes, cancellation, interruption, racing, timeouts, and supervision.
- Use Schedule for retry or recurrence. Do not build retry loops from timers.
- Use Queue, PubSub, Stream, Ref, Deferred, Semaphore, or STM according to the ownership and coordination problem.
- Avoid detached fibers. If detachment is required at a composition root, document its owner and termination condition.

### Product protocols

- Prefer Effect HTTP API for typed HTTP contracts, RPC for typed process boundaries, SQL integrations for persistence, and Effect CLI for command applications when those domains are present.
- Keep transport representations separate from domain values through schemas.
- Use `@effect/typeclass` when a lawful reusable algebra materially improves composition. Do not introduce typeclasses only to disguise a one-off function.

## Integrate React applications

Use this division of responsibility:

- Effect: decoding, capabilities, failures, resources, asynchronous computations, and service composition;
- XState: finite UI transitions, actor lifecycles, recovery states, and subscriptions;
- TanStack Query: ordinary remote server-state caching and mutation;
- TanStack DB: reactive external collections when local queries and synchronization justify it;
- React: rendering actor/query observations and local ephemeral form input.

Disallow ordinary `useEffect` in product components. Put browser subscriptions, timers, and long-lived callbacks in XState callback actors or library-owned subscriptions. A rare framework adapter may use `useEffect` only in a named adapter directory with a narrow lint override and a written ownership reason.

Enable React Compiler. Avoid manual `useMemo`, `useCallback`, and `memo` unless profiling or an external identity contract proves they are necessary. Enable React, Hooks, compiler-analysis, and JSX accessibility lint domains.

## Keep leaf computation direct

TypeScript is Effect's host syntax, not a second application architecture. Keep a
calculation as a direct function when it is total and has no dependency,
authority, failure, resource, or lifecycle to expose. Examples include:

- a small total transformation with no failure or capability;
- an immutable data constructor already guarded by a schema;
- a hot pure loop supported by a benchmark;
- a framework callback that only forwards a typed message into an Effect-owned program.

Direct external packages are acceptable only when reviewed as total,
authority-free dependencies with stable semantics. Otherwise expose the needed
functionality as a Service and confine the concrete import to its Layer. Ambient
configuration, raw external decoding, resource ownership, retries, cancellation,
operational concurrency, persistence boundaries, and application-level error
handling remain Effect-owned.

When an entire module is intentionally pure or adapter-specific, state its role in a short module comment or architecture map. Do not demand exemption comments for every local total function inside an Effect program.

## Enforce the architecture

Use several independent gates:

1. pin reviewed Effect and platform versions;
2. enable Effect TypeScript diagnostics and the Effect Oxlint plugin where compatible;
3. reject ambient console, clock, random, timer, environment, raw JSON, runtime execution, and cross-platform imports outside their declared domains;
4. reject `useEffect` outside reviewed adapters;
5. run strict TypeScript, Oxlint, Oxfmt, unit tests, and architecture acceptance journeys;
6. test at least one rejected input, typed failure, cancellation or release path, and deterministic derived artifact;
7. record narrow exceptions with a reason, owner, and removal condition.

Treat lint results and tests as evidence over their checked scope, not proof of total correctness.

## Review checklist

- Are all external values decoded before use?
- Are requirements still visible until the intended composition root?
- Does one component own each mutable resource and lifecycle?
- Are errors, interruption, retries, and release observable and typed?
- Are Fiber lifetimes bounded?
- Are Config and platform capabilities injected instead of ambient?
- Does Schema composition make representation changes readable?
- Does React render observations instead of secretly managing system lifecycles?
- Are concrete dependencies confined to Layer implementations while portable programs depend on Services?
- Does every custom Service add a domain contract or policy that an existing Effect service does not already provide?
- Is every direct external pure dependency explicitly reviewed and genuinely authority-free?
- Do the gates contain a counterexample that would fail if the policy regressed?
