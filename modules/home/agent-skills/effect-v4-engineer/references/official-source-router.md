# Official Effect source router

Use this router after recording the project's exact Effect version. Read only
the branches needed by the task. API names and signatures come from the pinned
source; this file only points to likely authoritative evidence.

Assume the official checkout is `../effect` relative to the project when it is
available. Resolve its actual path before reading.

## Start here

1. Read `LLMS.md` for the generated feature index.
2. Read `.agents/AGENTS.md` for repository-local Effect guidance.
3. Read the matching executable `ai-docs/src` example.
4. Confirm non-trivial APIs in `packages/effect/src`.
5. Confirm behavior and inference in `packages/effect/test` and
   `packages/effect/typetest`.

Generated prose and examples guide discovery. Source, runtime tests, and type
tests are the stronger evidence for the checked-out revision.

## Route by task

| Task | First official sources |
| --- | --- |
| Effect construction, `gen`, or `Effect.fn` | `ai-docs/src/01_effect/01_basics`, `packages/effect/src/Effect.ts` |
| Schema, brands, variants, codecs, parsing, or arbitrary generation | `SCHEMA.md`, `ai-docs/src/01_effect/02_schema`, `packages/effect/test/schema`, `packages/effect/typetest/schema` |
| Services, Layers, requirements, or test services | `ai-docs/src/01_effect/03_services`, `packages/effect/src/Context.ts`, `packages/effect/src/Layer.ts` |
| Typed errors and recovery | `ai-docs/src/01_effect/04_errors`, `packages/effect/src/Effect.ts`, Schema tagged-error tests |
| Resources, scopes, or background ownership | `ai-docs/src/01_effect/05_resources`, `packages/effect/src/Scope.ts`, resource tests |
| Runtime entry points or integration runtimes | `ai-docs/src/01_effect/06_running`, `ai-docs/src/04_integration`, platform runtime source and tests |
| Queues, PubSub, latest-value state, or event distribution | `ai-docs/src/01_effect/07_pubsub`, the corresponding module source and tests |
| Config or providers | the Config links in `LLMS.md`, `packages/effect/src/Config.ts`, `ConfigProvider.ts`, and tests |
| Retry, repeat, pacing, polling, or backoff | the Schedule links in `LLMS.md`, `packages/effect/src/Schedule.ts`, and tests |
| Cache, memoization, lookup deduplication, or batching | Cache links in `LLMS.md`, `packages/effect/src/Cache.ts`, `ai-docs/src/05_batching`, and tests |
| Streams, backpressure, or async event sources | Stream links in `LLMS.md`, `packages/effect/src/Stream.ts`, and stream tests |
| HTTP clients | `ai-docs/src/50_http-client`, HTTP client source and tests |
| HTTP servers or typed APIs | `ai-docs/src/51_http-server`, `packages/effect/src/unstable/httpapi`, and tests |
| Effect tests, time, or concurrent synchronization | `ai-docs/src/09_testing`, `packages/effect/src/testing`, and relevant tests |
| Child processes | `ai-docs/src/60_child-process`, process platform source and tests |
| SQL, RPC, CLI, AI, cluster, or another specialized domain | the matching top-level `ai-docs/src` directory, then its source, tests, and type tests |

## Native-first check

Before defining a project service or adding a package, search all three Effect
surfaces:

```text
effect core → effect platform → effect unstable
```

If Effect already models the capability, use its service and platform Layer.
Define a project service only when it adds domain contract or policy. For an
external dependency, inspect its exact peer dependency and execute one real
integration journey; a semver range is a claim, not compatibility evidence.

## Testing defaults

- Prefer `@effect/vitest` and `it.effect` for Effect programs.
- Use `TestClock` for time and schedules rather than wall-clock sleeps.
- Use `Deferred`, `Queue`, `Latch`, `Ref`, or a domain test service for
  deterministic fiber coordination.
- Keep success, typed failure, defects, interruption, and finalization distinct
  in assertions.
- Use runtime tests for behavior and Tstyche/type tests for inference or
  requirement-channel contracts.

## Prior art

The progressive task router and several selection prompts were informed by Kit
Langton's MIT-licensed Effect skill:
<https://github.com/kitlangton/skills/tree/main/skills/effect>.

The local skill deliberately does not vendor its API examples. Verify every
example against the pinned official Effect source before adopting it.
