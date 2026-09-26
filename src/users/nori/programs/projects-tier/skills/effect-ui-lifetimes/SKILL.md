---
name: effect-ui-lifetimes
description: Decides where Effect work lives in a Foldkit UI and who owns it. Keeps update and view pure, builds Commands and Mounts lazily, gives each Command, Mount, Subscription, and resource one owner, and states cancellation order and stale-result policy. Use when writing or reviewing Foldkit update, view, Command, Mount, Subscription, ManagedResource, or runtime resource code.
---

# Effect UI lifetimes (Foldkit)

This skill decides where Effect work lives in a Foldkit application, which
construct owns it, and how it stops. It prevents work that runs inside a pure
update, outlives its owner, or races its own cancellation. The house form of a
repository (module layout, shared Commands, test setup) is in `effect-house`.

## Look up first

- `node_modules/effect/AGENTS.md` sections: "Managing resources and `Scope`s",
  "Working with Streams", "Writing `Effect` code".
- `node_modules/effect/ai-docs/src/01_effect/05_resources/` for acquire and
  release inside Mounts and ManagedResources; `ai-docs/src/03_stream/` for the
  Streams behind Subscriptions and `Mount.defineStream`.
- `skill://foldkit` for the framing. It points at the project's vendored
  `repos/foldkit/` subtree (examples, AGENTS.md, skills, packages); match its
  example apps before you invent a shape.
- Without the subtree, the installed package is the contract: it ships only
  `dist`, and the JSDoc in `node_modules/foldkit/dist/**/*.d.ts` states the
  semantics. Read `command/`, `update/`, `subscription/`, `mount/`,
  `managedResource/`, `runtime/runtime.d.ts` (`resources`),
  `runtime/hostConnector.d.ts` (`dispose`), and `test/story.d.ts`,
  `test/scene.d.ts`. [references/foldkit-contracts.md](references/foldkit-contracts.md)
  lists the contracts this skill relies on.
- Establish the versions in the package that imports Foldkit; a Foldkit release
  pins the Effect release it was built against:

```sh
jq -r '.version, .peerDependencies.effect' node_modules/foldkit/package.json
jq -r .version node_modules/effect/package.json
```

Stop searching when every Foldkit and Effect API you will use has matching
installed guidance or source, or the search established that none exists (then
say so in your report).

## Decide

1. **Pure or work?** update, view, `modelToDependencies`,
   `modelToMaybeRequirements`, and interrupt keys are plain functions of the
   Model and the Message (FX014). They read no clock, random source, DOM, or
   storage, and run no Effect. Time, ids, and measurements arrive as Messages.
2. **Who owns the work?** Take the first row that fits:

| Work | Owner | Lives |
|---|---|---|
| One-shot work caused by a Message (request, save, focus) | `Command.define`, returned from update | Until done or interrupted |
| Work tied to a rendered element (measure, portal, observer, widget) | `Mount.define`, `Mount.defineStream` via `OnMount` | Element insert to removal |
| Events while a Model condition holds (timer, socket frames, keys) | `Subscription.make` entry; `Subscription.persistent` if Model-independent | Restarts when its dependencies change |
| Stateful resource while the Model is in a state (camera, socket, worker) | `ManagedResource.make` with `ManagedResource.tag` | Acquired and released as requirements change |
| App-wide singleton service (RPC client, audio graph) | runtime `resources` Layer (`effect-services-layers`) | Runtime start to teardown |

   A Command outlives the Submodel that returned it: it runs in the runtime
   scope, and `Update.foldChild` drops its result once the child is gone. Work
   that must stop with a page is interrupted when the page leaves, or becomes a
   gated Subscription (`Subscription.lift` with `when`) or a lifted
   ManagedResource. Work that must survive the page never lives in a Mount.
3. **Construction stays inert.** The runtime calls `execute` later, so building
   or discarding a Command or Mount runs nothing. Keep every read and call inside
   the returned Effect. A no-args `execute` is an Effect value built when the
   module loads: an argument evaluated while building it runs at import time, so
   defer reads with `Effect.sync` or `Effect.suspend`. Foldkit's own
   `Command.define` keeps an `Effect.suspend` that its source calls load
   bearing; no simplification removes such a suspension (FX013).
4. **Errors and requirements stay in the Effect.** `Update.Commands` accepts
   only Commands whose error channel is `never`: map each expected failure to a
   `Failed*` Message inside the Effect (`effect-errors-recovery`). A defect in a
   Command stops the dispatch loop and renders the crash view. Subscription
   Streams have no error channel; ManagedResource acquire failures arrive as
   `onAcquireError`. Services come from `resources`, a ManagedResource tag
   (`.get` fails with `ResourceNotAvailable` while inactive), or per Command
   through `Command.mapEffect`.
5. **Cancellation is addressed, not ordered.** Make only one-shot Commands
   interruptible: `interrupt: true` keys by name, `keyFields` with `toKey`
   keys by Model identity, never a generated value. A key is an address, not a
   lock: invocations under one key run concurrently, dispatch never interrupts,
   and one batch runs its Commands concurrently in no order. To replace, return
   `Definition.Interrupt` alone and dispatch the replacement from its
   `CompletedCancel<Name>` Message. Model-derived lifetimes use a Subscription
   or ManagedResource instead.
6. **State the stale-result policy.** An `Interrupted` outcome guarantees that
   the stopped holders never dispatch; `NotFound` means nothing held the key and
   the result may already be queued or handled. Carry the identity that produced
   a result (its args or key fields) in the result Message, and let update drop
   a result that no longer matches the Model. Model loading with `AsyncData`.
   Never rely on arrival order.
7. **Lift, do not re-wrap.** Lift child Messages through the recorded lifts:
   `Update.foldChild`, `h.submodel`, `Subscription.lift`,
   `ManagedResource.lift`, `Command.mapMessage`, `Command.mapMessages`.
   `Command.mapEffect` changes only the Effect (services, retry, delay); a
   Message lifted inside it is invisible to Story and Scene.
8. **No parallel scheduler.** Only the runtime (`Runtime.run`, `embed`,
   `hydrate`) runs UI Effects (FX003). Never add a queue, dispatcher,
   `Effect.run*` call, raw listener, or timer to route Messages or order
   Commands.

## Rules

| Rule | Requirement | Enforcement |
|---|---|---|
| FX014 pure-domain-core | update, view, dependency and requirement functions, and interrupt keys are total functions of Model and Message; no clock, random, generated id, or DOM read. | `effecttsgo/global-date`, `effecttsgo/global-random`, `effecttsgo/crypto-random-uuid`; test: Story tests run every Message and execute no Effect |
| FX007 lazy-construction | Building or discarding a Command or Mount runs nothing; every read sits inside the returned Effect. An Effect built in update or view and not returned as a Command never runs. | `effecttsgo/floating-effect`; test: construct and discard with a probe observes zero calls and no throw |
| FX006 owned-lifetime | Each piece of work has one owner (Command, Mount, Subscription, ManagedResource, `resources`); no timer, listener, or fork lives outside them. | `effecttsgo/global-timers`, `effecttsgo/global-timers-in-effect`; test: after unmount and `dispose` every finalizer receipt completes and no Message dispatches |
| FX009 explicit-order-capacity | A key addresses invocations and serializes nothing; a batch runs in no order. A replacement is dispatched from `CompletedCancel<Name>`, and each interruptible Command states its same-key and stale-result policy. | test: same-key repeats and a completion-versus-interrupt race follow the stated policy; review-only |
| FX005 honest-error-channel | Commands reach the runtime with error channel `never`: expected failures become `Failed*` Messages, defects stay defects, acquire failures reach `onAcquireError`. | test: an injected dependency failure yields the `Failed*` Message and the app keeps running; review-only |
| FX008 capability-preservation | Change a Command's Effect only with `Command.mapEffect` and lift Messages only through the recorded lifts; no cast narrows an error or requirement channel. | `effecttsgo/unsafe-effect-type-assertion`; test: a parent Story resolves a child Command and sees the lifted Message |
| FX003 owned-runtime-boundary | UI Effects run only in the Foldkit runtime; no `Effect.run*`, async handler, or hand-built queue dispatches Messages. A nested run is fixed by composing the inner Effect, not by another run function. | `effecttsgo/run-effect-inside-effect`, `effecttsgo/async-function`; review-only |
| FX011 intentional-observability | The runtime records each Command as a span named after it with its args as attributes: name Commands for the domain action and keep secrets and bulk data out of args. | review-only |

## Verify

- Recipes: [references/lifetime-tests.md](references/lifetime-tests.md). Story
  tests cover every Message: next Model, exact pending Commands, and
  resolution with success and `Failed*` results. Story never runs an Effect and
  fails on unresolved Commands.
- Construct and discard every Command and Mount with a probe; zero calls and no
  throw. Plausible bug: `execute` evaluated at construction.
- Lifetimes: `Runtime.embed` the app, drive the Model into and out of each
  owning state, then `dispose`. Await a finalizer receipt for every
  Subscription, ManagedResource, Mount, and in-flight Command. Cleanup is
  asynchronous: wait on receipts, never on sleeps or frames.
- Cancellation: same-key invocations both dispatch unless interrupted;
  `Interrupt` stops every holder; a completion that wins the race yields
  `NotFound` plus the stated stale-result handling; a replacement starts only
  after `CompletedCancel<Name>`.
- Scene tests drive view, Mount, Subscription, and ManagedResource transitions.
- The diagnostics in the Rules table are clean on touched files. Foldkit's
  source documents a `foldkit/prefer-command-mapmessage` lint rule; `effect-house`
  says whether the repository enables it.
- Host boundaries: a foreign library can end the page or process before
  finalizers run (OpenCode's spinner called process exit and skipped them). Test
  release through the real boundary, not only inside the Effect.

## Escape hatches

A browser or third-party API wrapped in a Mount, Subscription, or
ManagedResource with acquire and release is native composition, not an exception
(`effect-boundary-adapters`). A registered exception (`effect-review-exceptions`)
is needed for a listener, timer, or fiber outside those owners, an `Effect.run*`
call in UI code, or work that deliberately outlives its owner. The record names
`EX-NNNN`, rules, scope, reason, missingCapability, nativeAlternatives (Command,
Mount, Subscription, ManagedResource, `resources`), verification, owner,
examinedWith (the `foldkit` and `effect` versions), and retirementTrigger. Not a
justification: another framework's habit, familiarity, "could not find the
API", or a test that passes only with a sleep.

## Done means

- update, view, dependency and requirement functions, and keys are pure; Story
  tests cover every Message.
- Every piece of work has one owner from the table, with a stated stop.
- Every interruptible Command has a Model-derived key, a `CompletedCancel<Name>`
  handler, and a stated stale-result policy.
- Construct-and-discard, lifetime, and cancellation-race tests pass.
- Rules-table diagnostics are clean or name a registered exception.
- The report names the Foldkit and Effect versions, the checks run with their
  results, and the checks not run.
