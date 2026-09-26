# Foldkit contracts this skill relies on

Read against Foldkit 0.163.0 (peer `effect` 4.0.0-rc.116), installed
`node_modules/foldkit/dist`. Re-read the named file when the installed version
differs; the JSDoc there is the authority, not this summary.

| Contract | Where it is stated |
|---|---|
| Constructing a Command never runs `execute`; a discarded Command runs nothing. With `args`, `execute` is wrapped in `Effect.suspend`; a no-args `execute` is already an Effect value. | `command/index.d.ts` (`define`), `command/index.js` (the load-bearing suspend) |
| A key is an address, not a lock: invocations under one key run concurrently, dispatching never interrupts, and only an Interrupt Command interrupts. | `command/index.d.ts` (`define`), `command/interruptible/interruptible.d.ts` |
| `Definition.Interrupt` stops every holder; outcome `Interrupted` (stopped holders never dispatch) or `NotFound`. Name the result `CompletedCancel<Name>`. | same files, `Outcome` |
| Commands in one batch run concurrently in no order; `[Interrupt, Next]` in one list is a race. Sequence through the Interrupt's result Message. | `command/index.d.ts` (`define`), `update/update.d.ts` (`Commands`, `combine`) |
| Keys derive from Model identity, never a generated value; update is pure. | `command/index.d.ts` (`InterruptOption`) |
| `Update.Commands` requires error channel `never`. A Command whose Effect fails with a cause crashes the runtime into the crash view. | `update/update.d.ts`, `runtime/runtime.js` (`forkCommand`), `runtime/crashUI.d.ts` |
| The runtime forks each Command one microtask later into the runtime scope, wrapped in a span named after the Command with its args as attributes. | `runtime/runtime.js` (`forkCommand`) |
| `Update.foldChild` returns `{ model }` when `read` returns `None`: a Message for an unmounted child is a no-op. | `update/update.d.ts` (`foldChild`) |
| `Command.mapEffect` must not lift the result Message; `mapMessage` and `mapMessages` record the lift for `Story.Command.resolve` and `Scene.Command.resolve`. | `command/index.d.ts` |
| A Subscription restarts when its dependencies change (unless `keepAliveEquivalence`, an escape hatch for fast-changing reads); its Stream has error channel `never`. `Subscription.persistent` ignores the Model. A closed `when` gate on `Subscription.lift` tears the Stream down. | `subscription/subscription.d.ts` |
| ManagedResource: None to Some acquires, Some to a different Some releases then re-acquires, Some to None releases; acquire failure dispatches `onAcquireError` and watching continues; `acquire` runs with the resource Scope; `.get` fails with `ResourceNotAvailable` while inactive. | `managedResource/managedResource.d.ts` |
| `resources` Layer: built once when first needed, shared for the application's lifetime, released at teardown; a build failure crashes the app. Cheap or varying services belong inside the Command's Effect. | `runtime/runtime.d.ts` (`resources`) |
| Mount: `execute` runs when the element enters the DOM; its scope lasts until the element is removed; cleanup is forked (asynchronous); construct resources inside the acquire body; args are captured at mount. Model-driven DOM work after mount goes through a Command. | `mount/index.d.ts` (`define`, `defineStream`) |
| `Runtime.embed` returns a handle whose idempotent `dispose` interrupts the runtime and stops Subscriptions, ManagedResources, Mounts, listeners, and in-flight Commands. | `runtime/start.d.ts`, `runtime/hostConnector.d.ts` |
| Story runs update only: Commands stay pending until resolved, and the story fails on unresolved Commands. Scene adds the view, Mounts, Subscription Messages, and ManagedResource lifecycle steps. | `test/story.d.ts`, `test/scene.d.ts` |
